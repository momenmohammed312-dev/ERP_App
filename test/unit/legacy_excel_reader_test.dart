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
import 'package:pos_offline_desktop/services/attendance/legacy_excel_reader.dart';

/// باني BIFF2 مرن: labels + number + formula + سجلات خام.
Uint8List buildBiff({
  List<List<String>> labels = const [],
  List<(int, int, double)> formulas = const [],
  List<int> tailBytes = const [],
}) {
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

  void label(int r, int c, String s) {
    final bytes = latin1.encode(s);
    rec(0x0004, [
      r & 0xFF, (r >> 8) & 0xFF,
      c & 0xFF, (c >> 8) & 0xFF,
      0x41, 0x00, 0x00, bytes.length, ...bytes,
    ]);
  }

  rec(0x0809, [0, 0, 0, 0, 0, 0]);
  for (var r = 0; r < labels.length; r++) {
    for (var c = 0; c < labels[r].length; c++) {
      label(r, c, labels[r][c]);
    }
  }
  for (final (r, c, v) in formulas) {
    final bits = ByteData(8)..setFloat64(0, v, Endian.little);
    rec(0x0006, [
      r & 0xFF, (r >> 8) & 0xFF,
      c & 0xFF, (c >> 8) & 0xFF,
      0x41, 0x00, 0x00, ...bits.buffer.asUint8List(),
      // 4 بايت توكن فارغة لاستيفاء الحد الأدنى للطول
      0x00, 0x00, 0x00, 0x00,
    ]);
  }
  out.add(tailBytes);
  rec(0x000A, []);
  return out.toBytes();
}

List<List<String>> zkHeader() => [
      [
        'Department', 'Name', 'No.', 'Date/Time', 'Status',
        'Location ID', 'ID Number', 'Workcode', 'VerifyCode', 'CardNo',
      ],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  AttendanceFileImportService serviceFor(AppDatabase db) {
    final deviceDao = AttendanceDeviceDao(db);
    final staffDao = StaffManagementDao(db);
    final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    return AttendanceFileImportService(
      deviceDao,
      staffDao,
      AttendanceSyncService(deviceDao, staffDao, engine),
    );
  }

  group('legacy BIFF2 hardening', () {
    test('formula numeric cell (date serial) is read as date text', () {
      // 45918.5 = 2025-09-18 12:00 في ترميز إكسل المسلسل
      final bytes = buildBiff(
        labels: [
          ...zkHeader(),
          ['OUR COMPANY', 'F1', '201', '', 'C/In', '1', '', '0', 'FP', '1'],
        ],
        formulas: [(1, 3, 45918.5)],
      );
      final result = LegacyExcelReader.readBiff2Detailed(bytes);
      // الخلية الفارغة أولاً ثم المعادلة فوقها → تحذير مكررة متوقع وموثق
      expect(
        result.warnings.any((w) => w.contains('مكررة')),
        isTrue,
      );
      expect(result.grid[1][3], startsWith('2025-09-18'));
      expect(result.grid[1][3], contains('12:00:00'));
    });

    test('corrupt tail stops with a warning, keeps valid rows', () {
      final bytes = buildBiff(
        labels: [
          ...zkHeader(),
          ['OUR COMPANY', 'F1', '201', '9/1/2026 8:00:00 AM', 'C/In'],
        ],
        // سجل تالف: طول ضخم غير صالح ثم بايتات عشوائية
        tailBytes: [0x04, 0x00, 0xFF, 0xFF, 0x01, 0x02, 0x03],
      );
      final result = LegacyExcelReader.readBiff2Detailed(bytes);
      expect(result.grid.length, 2);
      expect(
        result.warnings.any((w) => w.contains('توقفت القراءة')),
        isTrue,
      );
    });

    test('duplicated grid warns and keeps last values', () {
      final once = buildBiff(labels: [
        ...zkHeader(),
        ['OUR COMPANY', 'F1', '201', '9/1/2026 8:00:00 AM', 'C/In'],
      ]);
      // محاكاة ورقتين مدمجتين: نفس البايتات مرتين
      final twice = BytesBuilder()
        ..add(once)
        ..add(once);
      final result =
          LegacyExcelReader.readBiff2Detailed(twice.toBytes());
      expect(result.grid.length, 2);
      expect(result.sheetCount, 2);
      expect(
        result.warnings.any((w) => w.contains('مدمجة') || w.contains('مكررة')),
        isTrue,
      );
    });

    test('blank rows are dropped but reported', () {
      final bytes = buildBiff(labels: [
        ...zkHeader(),
        ['OUR COMPANY', 'F1', '201', '9/1/2026 8:00:00 AM', 'C/In'],
        ['', '', '', '', '', '', '', '', '', ''],
      ]);
      final result = LegacyExcelReader.readBiff2Detailed(bytes);
      expect(result.grid.length, 2);
      expect(
        result.warnings.any((w) => w.contains('فارغ')),
        isTrue,
      );
    });
  });

  group('import service date robustness', () {
    test('excel serial + yyyy/MM/dd dates parse and import', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final svc = serviceFor(db);

      final bytes = buildBiff(labels: [
        ...zkHeader(),
        // تاريخ مسلسل عبر FORMULA + تاريخ بشرطة مائلة معكوسة
        ['OUR COMPANY', 'S1', '301', '', 'C/In', '1', '', '0', 'FP', '1'],
        ['OUR COMPANY', 'S1', '301', '2026/09/02', 'C/Out', '1', '', '0', 'FP', '1'],
      ], formulas: [
        (1, 3, 45918.0), // 2025-09-18
      ]);
      final preview = await svc.parseFile(bytes: bytes, fileName: 's.xls');
      expect(preview.columnsDetected, isTrue);
      // بصمة بتاريخ مسلسل + بصمة بتاريخ مائل (IDs مختلفة عن بعض؟ لا — نفس الـID)
      expect(preview.punches.length, 2);
      expect(
        preview.punches.any((p) => p.time.year == 2025),
        isTrue,
        reason: 'التاريخ المسلسل يُفهم',
      );
      expect(
        preview.punches.any((p) =>
            p.time.year == 2026 && p.time.month == 9 && p.time.day == 2),
        isTrue,
        reason: 'yyyy/MM/dd يُفهم',
      );
    });

    test('rows with data but no id/date are counted as blank, not silent',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final svc = serviceFor(db);

      final bytes = buildBiff(labels: [
        ...zkHeader(),
        ['OUR COMPANY', 'S1', '301', '9/1/2026 8:00:00 AM', 'C/In'],
        ['stray note', '', '', '', ''],
      ]);
      final preview = await svc.parseFile(bytes: bytes, fileName: 'b.xls');
      expect(preview.punches.length, 1);
      expect(preview.blankRows, 1);
    });

    test('reader warnings surface in the preview', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final svc = serviceFor(db);

      final bytes = buildBiff(
        labels: [
          ...zkHeader(),
          ['OUR COMPANY', 'S1', '301', '9/1/2026 8:00:00 AM', 'C/In'],
        ],
        tailBytes: [0x04, 0x00, 0xFF, 0xFF, 0x09],
      );
      final preview = await svc.parseFile(bytes: bytes, fileName: 'w.xls');
      expect(preview.punches.length, 1);
      expect(preview.warnings, isNotEmpty);
      expect(preview.rowsRead, 2);
    });
  });
}
