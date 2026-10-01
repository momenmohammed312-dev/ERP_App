import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_file_import_service.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';

/// يبني ملف BIFF2 مصغّر (نفس بنية تصدير ZKTeco) داخل الذاكرة.
Uint8List buildBiff2(List<List<String>> rows) {
  final out = BytesBuilder();
  void rec(int type, List<int> payload) {
    out.add([
      type & 0xFF,
      (type >> 8) & 0xFF,
      payload.length & 0xFF,
      (payload.length >> 8) & 0xFF,
    ]);
    out.add(payload);
  }

  rec(0x0809, [0, 0, 0, 0, 0, 0]); // BOF
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final bytes = latin1.encode(rows[r][c]);
      rec(0x0004, [
        r & 0xFF,
        (r >> 8) & 0xFF,
        c & 0xFF,
        (c >> 8) & 0xFF,
        0x41,
        0x00,
        0x00,
        bytes.length,
        ...bytes,
      ]);
    }
  }
  rec(0x000A, []); // EOF
  return out.toBytes();
}

List<List<String>> zkRows() => [
      [
        'Department',
        'Name',
        'No.',
        'Date/Time',
        'Status',
        'Location ID',
        'ID Number',
        'Workcode',
        'VerifyCode',
        'CardNo',
      ],
      [
        'OUR COMPANY',
        'TestOne',
        '101',
        '9/1/2026 8:05:00 AM',
        'C/In',
        '1',
        '',
        '0',
        'FP',
        '111',
      ],
      [
        'OUR COMPANY',
        'TestOne',
        '101',
        '9/1/2026 5:10:00 PM',
        'C/Out',
        '1',
        '',
        '0',
        'FP',
        '111',
      ],
      [
        'OUR COMPANY',
        'TestTwo',
        '102',
        '9/1/2026 8:20:00 AM',
        'C/In',
        '1',
        '',
        '0',
        'FP',
        '222',
      ],
      [
        'OUR COMPANY',
        'TestTwo',
        '102',
        'NOT A DATE',
        'C/Out',
        '1',
        '',
        '0',
        'FP',
        '222',
      ],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  group('ZK excel parsing', () {
    test('BIFF2 header + punches + bad row skipped', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final preview = await svc.parseFile(
        bytes: buildBiff2(zkRows()),
        fileName: 'test.xls',
      );

      expect(preview.columnsDetected, isTrue);
      expect(preview.punches.length, 3);
      expect(preview.distinctIds, 2);
      expect(preview.skippedRows, 1);
      expect(preview.errors, isNotEmpty);
      expect(
        preview.punches.map((p) => p.eventType).toList(),
        ['check_in', 'check_in', 'check_out'],
      );
      expect(preview.punches.first.externalId, '101');
      expect(preview.punches.first.name, 'TestOne');
      expect(preview.punches.first.time, DateTime(2026, 9, 1, 8, 5));
      expect(preview.minTime, DateTime(2026, 9, 1, 8, 5));
      expect(preview.maxTime, DateTime(2026, 9, 1, 17, 10));
    });

    test('CSV with same layout parses too', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final csv = zkRows().take(3).map((r) => r.join(',')).join('\n');
      final preview = await svc.parseFile(
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileName: 'test.csv',
      );

      expect(preview.columnsDetected, isTrue);
      expect(preview.punches.length, 2);
      expect(preview.punches.last.eventType, 'check_out');
    });

    test('unknown layout is rejected, not misimported', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final preview = await svc.parseFile(
        bytes: buildBiff2([
          ['foo', 'bar'],
          ['hello', 'world'],
        ]),
        fileName: 'weird.xls',
      );

      expect(preview.columnsDetected, isFalse);
      expect(preview.punches, isEmpty);
    });
  });

  group('ZK excel import pipeline', () {
    test('unknown IDs are skipped, not created as new staff', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final preview = await svc.parseFile(
        bytes: buildBiff2(zkRows()),
        fileName: 'test.xls',
      );

      expect(preview.matchedIds, 0);
      expect(preview.unknownIds, 2);
      expect(preview.invalidIds, 0);
      expect(preview.importablePunches, 0);
      expect(preview.skippedUnknownPunches, 3);

      final result = await svc.importPunches(preview);
      expect(result.error, isNull);
      expect(result.fetched, 0);
      expect(result.matched, 0);
      expect(result.newStaff, 0);
      expect(result.skippedUnknown, 3);
      expect(result.unknownIds, isNotEmpty);
      // لا موظف جديد ولا سجل حضور — التحقق مبعوض كل حاجة
      expect(await staffDao.getAllStaff(), isEmpty);
      expect(await staffDao.getAttendanceByStaff('STAFF0001'), isEmpty);
      expect(await deviceDao.getAllDevices(), isNotEmpty); // جهاز الاستيراد فقط
    });

    test('ID already enrolled on a real device reuses the same staff', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      // جهاز حقيقي + موظف موجود مربوط ببصمة 101
      final now = DateTime.now();
      final realDeviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'BIO-001',
          name: 'البوابة الرئيسية',
          connectionType: 'tcp_ip',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'ST-101',
          name: 'أحمد صادق',
          position: 'موظف',
          employmentType: 'full_time',
          basicSalary: 1000,
          hireDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: 'ST-101',
          deviceId: realDeviceId,
          externalUserId: '101',
          enrollmentStatus: 'enrolled',
          createdAt: now,
          updatedAt: now,
        ),
      );
      // 102 مربوط كمان
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'ST-102',
          name: 'سعيد كامل',
          position: 'موظف',
          employmentType: 'full_time',
          basicSalary: 1000,
          hireDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: 'ST-102',
          deviceId: realDeviceId,
          externalUserId: '102',
          enrollmentStatus: 'enrolled',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final preview = await svc.parseFile(
        bytes: buildBiff2(zkRows()),
        fileName: 'test.xls',
      );

      expect(preview.matchedIds, 2);
      expect(preview.unknownIds, 0);
      expect(preview.importablePunches, 3);
      expect(
        preview.idChecks
            .firstWhere((c) => c.externalId == '101')
            .staffId,
        'ST-101',
      );

      final result = await svc.importPunches(preview);
      expect(result.error, isNull);
      expect(result.matched, 3);
      expect(result.newStaff, 0, reason: 'ما ينفعش يتعمل موظف جديد');
      expect(result.linkedIds, 2, reason: 'ربطنا الـIDs على جهاز الاستيراد');
      expect(result.skippedUnknown, 0);

      // مافيش موظف ثالث، والاسم الأصلي ما اتغيرش
      final all = await staffDao.getAllStaff();
      expect(all.length, 2);
      expect(
        all.map((s) => s.staffId).toSet(),
        {'ST-101', 'ST-102'},
      );
      expect(
        (await staffDao.getStaffById('ST-101'))!.name,
        'أحمد صادق',
        reason: 'الاسم في الملف ما يغيّرش اسم الموظف الموجود',
      );

      // سجلات الحضور اتكتبت لنفس الموظف
      final rows101 = await staffDao.getAttendanceOnDate(
        'ST-101',
        DateTime(2026, 9, 1),
      );
      expect(rows101.length, 1);
      expect(rows101.first.checkInTime?.hour, 8);
      expect(rows101.first.checkOutTime?.hour, 17);
      final rows102 = await staffDao.getAttendanceOnDate(
        'ST-102',
        DateTime(2026, 9, 1),
      );
      expect(rows102.length, 1);
    });

    test('ID with empty name still matches by fingerprint ID', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final now = DateTime.now();
      final realDeviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'BIO-001',
          name: 'البوابة',
          connectionType: 'tcp_ip',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'ST-77',
          name: 'موظف بلا اسم في الملف',
          position: 'موظف',
          employmentType: 'full_time',
          basicSalary: 500,
          hireDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: 'ST-77',
          deviceId: realDeviceId,
          externalUserId: '77',
          enrollmentStatus: 'enrolled',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // نفس الملف بس: كل الأرقام = 77 وكل الأسماء فاضية
      final rows = zkRows();
      for (final r in rows.skip(1)) {
        r[1] = '';
        if (r[2] == '101' || r[2] == '102') r[2] = '77';
      }
      rows.removeWhere((r) => r[3] == 'NOT A DATE');

      final preview = await svc.parseFile(
        bytes: buildBiff2(rows),
        fileName: 'test.xls',
      );
      expect(preview.punches.every((p) => p.name.isEmpty), isTrue);
      expect(preview.matchedIds, 1);
      expect(preview.importablePunches, 3);

      final result = await svc.importPunches(preview);
      expect(result.matched, 3);
      expect(result.newStaff, 0);
      final attendance = await staffDao.getAttendanceOnDate(
        'ST-77',
        DateTime(2026, 9, 1),
      );
      expect(attendance.length, 1);
    });

    test('inactive staff and revoked mapping are skipped with a reason', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final now = DateTime.now();
      final realDeviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'BIO-001',
          name: 'البوابة',
          connectionType: 'tcp_ip',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'ST-101',
          name: 'منتهي الخدمة',
          position: 'موظف',
          employmentType: 'full_time',
          basicSalary: 1000,
          hireDate: now,
          status: 'terminated',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: 'ST-101',
          deviceId: realDeviceId,
          externalUserId: '101',
          enrollmentStatus: 'enrolled',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'ST-102',
          name: 'بصمة ملغاة',
          position: 'موظف',
          employmentType: 'full_time',
          basicSalary: 1000,
          hireDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: 'ST-102',
          deviceId: realDeviceId,
          externalUserId: '102',
          enrollmentStatus: 'revoked',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final preview = await svc.parseFile(
        bytes: buildBiff2(zkRows()),
        fileName: 'test.xls',
      );
      expect(preview.matchedIds, 0);
      expect(preview.invalidIds, 2);
      expect(preview.importablePunches, 0);
      expect(preview.invalidIdList.join(' '), contains('terminated'));
      expect(preview.invalidIdList.join(' '), contains('revoked'));

      final result = await svc.importPunches(preview);
      expect(result.matched, 0);
      expect(result.skippedInvalid, 3);
      expect(result.invalidIds.length, 2);
    });

    test('card number alone is not enough — row is skipped', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final rows = <List<String>>[
        zkRows().first,
        // No. فاضي، ID Number فاضي، بس فيه كارت
        ['OUR COMPANY', 'KartOnly', '', '9/1/2026 8:00:00 AM', 'C/In', '1', '', '0', 'FP', '999'],
      ];
      final preview = await svc.parseFile(
        bytes: buildBiff2(rows),
        fileName: 'test.xls',
      );
      expect(preview.punches, isEmpty);
      expect(preview.skippedRows, 1);
      expect(preview.errors.join(' '), contains('رقم بصمة'));
    });

    test('reimport dedups and does not duplicate attendance', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceFileImportService(
        deviceDao,
        staffDao,
        AttendanceSyncService(deviceDao, staffDao, engine),
      );

      final now = DateTime.now();
      final realDeviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'BIO-001',
          name: 'البوابة',
          connectionType: 'tcp_ip',
          createdAt: now,
          updatedAt: now,
        ),
      );
      for (final id in ['101', '102']) {
        await staffDao.addStaff(
          StaffTableCompanion.insert(
            staffId: 'ST-$id',
            name: 'موظف $id',
            position: 'موظف',
            employmentType: 'full_time',
            basicSalary: 1000,
            hireDate: now,
            status: 'active',
            createdAt: now,
            updatedAt: now,
          ),
        );
        await deviceDao.addMapping(
          StaffBiometricMappingsCompanion.insert(
            staffId: 'ST-$id',
            deviceId: realDeviceId,
            externalUserId: id,
            enrollmentStatus: 'enrolled',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      final first = await svc.importPunches(
        await svc.parseFile(bytes: buildBiff2(zkRows()), fileName: 'a.xls'),
      );
      expect(first.matched, 3);
      expect(first.newStaff, 0);

      final second = await svc.importPunches(
        await svc.parseFile(bytes: buildBiff2(zkRows()), fileName: 'a.xls'),
      );
      expect(second.error, isNull);
      expect(second.duplicate, 3);
      expect(second.matched, 0);
      expect(second.newStaff, 0);

      expect((await staffDao.getAllStaff()).length, 2);
      expect(
        (await staffDao.getAttendanceOnDate('ST-101', DateTime(2026, 9, 1)))
            .length,
        1,
      );
    });
  });
}
