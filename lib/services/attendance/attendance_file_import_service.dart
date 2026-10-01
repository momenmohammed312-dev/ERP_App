import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'attendance_sync_service.dart';
import 'legacy_excel_reader.dart';

/// بصمة واحدة مستخرجة من ملف (صف = حركة دخول/خروج).
class AttendanceFilePunch {
  /// رقم البصمة في جهاز الحضور (عمود No. ثم ID Number). الاسم مش شرط
  /// للمطابقة — الربط بالرقم فقط.
  final String externalId;
  final String name;
  final DateTime time;

  /// 'check_in' | 'check_out' | 'unknown'
  final String eventType;
  final String rawStatus;
  final String verifyCode;
  final String cardNo;
  final String department;

  const AttendanceFilePunch({
    required this.externalId,
    required this.name,
    required this.time,
    required this.eventType,
    required this.rawStatus,
    required this.verifyCode,
    required this.cardNo,
    required this.department,
  });
}

/// حالة رقم البصمة في الملف بعد التحقق من قاعدة البيانات.
enum AttendanceFileIdStatus {
  /// مربوط بالفعل بموظف (على جهاز الاستيراد أو أي جهاز حقيقي).
  matched,

  /// الرقم غير معروف: مافيش أي موظف مربوط بيه.
  unknown,

  /// الرقم معروف لكن الموظف غير صالح للاستقبال (منتهٍ/غير نشط/موقوف).
  invalid,
}

/// نتيجة التحقق لرقم بصمة واحد في الملف.
class AttendanceFileIdCheck {
  final String externalId;
  final String? staffId;
  final String? staffName;
  final AttendanceFileIdStatus status;
  final String? reason;
  final int punchCount;
  final bool boundOnImportDevice;

  const AttendanceFileIdCheck({
    required this.externalId,
    required this.status,
    required this.punchCount,
    this.staffId,
    this.staffName,
    this.reason,
    this.boundOnImportDevice = false,
  });
}

/// نتيجة تحليل الملف قبل التنفيذ (تُعرض في حوار التأكيد).
class AttendanceFilePreview {
  final String fileName;
  final List<AttendanceFilePunch> punches;
  final int skippedRows;
  final List<String> errors;
  final int alreadyMapped;
  final bool columnsDetected;

  /// عدد صفوف الشبكة المقروءة من الملف (قبل الترشيح) — للمقارنة بعدد
  /// صفوف الإكسل والتأكد أن القارئ لم يسقط شيئاً بصمت.
  final int rowsRead;

  /// تحذيرات القارئ (توقف مبكر، أوراق مدمجة، خلايا مكررة/تالفة...).
  final List<String> warnings;

  /// صفوف فيها بيانات لكن بلا رقم بصمة ولا تاريخ (تُتجاهل بعدّ).
  final int blankRows;

  /// نتيجة التحقق لكل رقم بصمة مميز في الملف (المطابقة بالـID فقط —
  /// الاسم مش شرط).
  final List<AttendanceFileIdCheck> idChecks;

  const AttendanceFilePreview({
    required this.fileName,
    required this.punches,
    required this.skippedRows,
    required this.errors,
    required this.alreadyMapped,
    required this.columnsDetected,
    this.idChecks = const [],
    this.rowsRead = 0,
    this.warnings = const [],
    this.blankRows = 0,
  });

  int get distinctIds => punches.map((p) => p.externalId).toSet().length;
  int get unmapped => distinctIds - alreadyMapped;

  int get matchedIds =>
      idChecks.where((c) => c.status == AttendanceFileIdStatus.matched).length;
  int get unknownIds =>
      idChecks.where((c) => c.status == AttendanceFileIdStatus.unknown).length;
  int get invalidIds =>
      idChecks.where((c) => c.status == AttendanceFileIdStatus.invalid).length;
  int get importablePunches => idChecks
      .where((c) => c.status == AttendanceFileIdStatus.matched)
      .fold(0, (sum, c) => sum + c.punchCount);
  int get skippedUnknownPunches => idChecks
      .where((c) => c.status == AttendanceFileIdStatus.unknown)
      .fold(0, (sum, c) => sum + c.punchCount);
  int get skippedInvalidPunches => idChecks
      .where((c) => c.status == AttendanceFileIdStatus.invalid)
      .fold(0, (sum, c) => sum + c.punchCount);
  List<String> get unknownIdList =>
      idChecks
          .where((c) => c.status == AttendanceFileIdStatus.unknown)
          .map((c) => '${c.externalId} (${c.punchCount} بصمة)')
          .toList();
  List<String> get invalidIdList => idChecks
      .where((c) => c.status == AttendanceFileIdStatus.invalid)
      .map(
        (c) => '${c.externalId}${c.staffName == null ? '' : ' — ${c.staffName}'}'
            ' (${c.punchCount} بصمة): ${c.reason ?? 'غير صالح'}',
      )
      .toList();

  DateTime? get minTime => punches.isEmpty
      ? null
      : punches.map((p) => p.time).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get maxTime => punches.isEmpty
      ? null
      : punches.map((p) => p.time).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// نتيجة تنفيذ الاستيراد الفعلي في القاعدة.
class AttendanceFileImportResult {
  final int fetched;
  final int matched;
  final int unmatched;
  final int duplicate;
  final int linkedIds;
  final int newStaff;
  final int renamed;
  final int skippedUnknown;
  final int skippedInvalid;

  /// سجلات الغياب التلقائية المولدة للأيام المغلقة في نطاق الملف.
  final int absencesCreated;

  final List<String> unknownIds;
  final List<String> invalidIds;
  final List<String> unmatchedSamples;
  final List<String> errors;
  final String? error;

  const AttendanceFileImportResult({
    required this.fetched,
    required this.matched,
    required this.unmatched,
    required this.duplicate,
    required this.newStaff,
    required this.renamed,
    required this.unmatchedSamples,
    required this.errors,
    this.linkedIds = 0,
    this.skippedUnknown = 0,
    this.skippedInvalid = 0,
    this.absencesCreated = 0,
    this.unknownIds = const [],
    this.invalidIds = const [],
    this.error,
  });
}

/// استيراد الحضور من ملف إكسل مُصدَّر من جهاز البصمة (ZKTeco ونحوه).
///
/// يقبل .xls القديم (BIFF2 عبر [LegacyExcelReader]) و.xlsx (حزمة excel)
/// و.csv، ثم يحوّل الصفوف إلى أحداث خام على جهاز افتراضي من نوع
/// `file_import` ويمررها على نفس خط المعالجة [AttendanceSyncService.processPendingEvents]
/// (مطابقة بالبصمة، إنشاء تلقائي، انصراف الفجر، شفاء الغياب، حساب
/// التأخير/الإضافي) — فلا منطق حسابي مكرر هنا.
class AttendanceFileImportService {
  static const importDeviceCode = 'FILE-IMPORT';
  static const importDeviceName = 'استيراد ملف إكسل';

  final AttendanceDeviceDao _deviceDao;
  final StaffManagementDao _staffDao;
  final AttendanceSyncService _sync;

  AttendanceFileImportService(this._deviceDao, this._staffDao, this._sync);

  // ── تحليل الملف ────────────────────────────────────────────────

  /// يحلّل بايتات الملف ويرجع معاينة (لا يكتب شيئاً في القاعدة).
  Future<AttendanceFilePreview> parseFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.split('.').last.toLowerCase();
    final detailed = _readGridDetailed(bytes, ext);
    final grid = detailed.grid;
    if (grid.isEmpty) {
      return AttendanceFilePreview(
        fileName: fileName,
        punches: const [],
        skippedRows: 0,
        errors: const ['الملف فارغ أو تعذّرت قراءته'],
        alreadyMapped: 0,
        columnsDetected: false,
        rowsRead: 0,
        warnings: detailed.warnings,
      );
    }
    final columns = _detectColumns(grid);
    final punches = <AttendanceFilePunch>[];
    final errors = <String>[];
    var skipped = 0;
    var blank = 0;
    if (columns == null) {
      return AttendanceFilePreview(
        fileName: fileName,
        punches: const [],
        skippedRows: grid.length,
        errors: const [
          'تعذّر التعرّف على أعمدة الملف — تأكد أنه تقرير حضور مُصدَّر من جهاز البصمة',
        ],
        alreadyMapped: 0,
        columnsDetected: false,
        rowsRead: detailed.rowsRead,
        warnings: detailed.warnings,
      );
    }
    for (var r = columns.dataStartRow; r < grid.length; r++) {
      final row = grid[r];
      String cell(int? idx) =>
          (idx == null || idx >= row.length) ? '' : row[idx].trim();
      // رقم البصمة = عمود No. ثم ID Number فقط. رقم الكارت ليس بصمة،
      // فوجود الكارت وحده لا يكفي — الصف يُتخطى بتقرير.
      final pin = cell(columns.idCol);
      final idNumber = cell(columns.idNumberCol);
      final id = pin.isNotEmpty ? pin : idNumber;
      final cardOnly = id.isEmpty && cell(columns.cardCol).isNotEmpty;
      final dateRaw = cell(columns.dateCol);
      final timeRaw = columns.timeCol != null ? cell(columns.timeCol) : '';
      // صف فارغ فعلياً — يُحتسب (كان يُتجاهل بصمت ويُربك عدّ الصفوف).
      if (id.isEmpty && dateRaw.isEmpty) {
        blank++;
        continue;
      }
      final time = _parseDateTime(dateRaw, timeRaw);
      if (id.isEmpty || time == null) {
        skipped++;
        if (errors.length < 10) {
          errors.add(
            cardOnly
                ? 'صف ${r + 1}: فيه رقم كارت (${cell(columns.cardCol)}) بدون رقم بصمة — تم التجاوز'
                : 'صف ${r + 1}: ${id.isEmpty ? 'رقم البصمة (No. / ID Number) فارغ' : 'تاريخ غير مفهوم "$dateRaw${timeRaw.isEmpty ? '' : ' $timeRaw'}"'} — تم التجاوز',
          );
        }
        continue;
      }
      punches.add(
        AttendanceFilePunch(
          externalId: id,
          name: cell(columns.nameCol),
          time: time,
          eventType: _normalizeStatus(cell(columns.statusCol)),
          rawStatus: cell(columns.statusCol),
          verifyCode: cell(columns.verifyCol),
          cardNo: cell(columns.cardCol),
          department: cell(columns.deptCol),
        ),
      );
    }
    punches.sort((a, b) => a.time.compareTo(b.time));

    final idChecks = await _validateIds(punches);
    var alreadyMapped = idChecks
        .where((c) => c.boundOnImportDevice)
        .length;

    return AttendanceFilePreview(
      fileName: fileName,
      punches: punches,
      skippedRows: skipped,
      errors: errors,
      alreadyMapped: alreadyMapped,
      columnsDetected: true,
      idChecks: idChecks,
      rowsRead: detailed.rowsRead,
      warnings: detailed.warnings,
      blankRows: blank,
    );
  }

  /// التحقق من كل رقم بصمة مميز في الملف قبل أي كتابة.
  ///
  /// المطابقة بالـID فقط (الاسم مش شرط): موظف مربوط بنفس البصمة على **أي**
  /// جهاز = نفس الموظف. رقم مجهول = تخطي وتقرير. موظف غير نشط/منتهٍ أو
  /// ربط مرفوض = تخطي مع السبب.
  Future<List<AttendanceFileIdCheck>> _validateIds(
    List<AttendanceFilePunch> punches,
  ) async {
    final countsById = <String, int>{};
    final namesById = <String, String>{};
    for (final p in punches) {
      countsById.update(
        p.externalId,
        (c) => c + 1,
        ifAbsent: () => 1,
      );
      if (p.name.trim().isNotEmpty) {
        namesById.putIfAbsent(p.externalId, () => p.name.trim());
      }
    }
    if (countsById.isEmpty) return const [];

    BiometricDevice? importDevice;
    try {
      importDevice = await _ensureImportDevice();
    } catch (_) {}

    final checks = <AttendanceFileIdCheck>[];
    for (final entry in countsById.entries) {
      final externalId = entry.key;
      final count = entry.value;
      final excelName = namesById[externalId];

      StaffBiometricMapping? importBinding;
      if (importDevice != null) {
        importBinding = await _deviceDao.getMappingRecordByExternalId(
          importDevice.id,
          externalId,
        );
      }

      // 1) ربط موجود بالفعل على جهاز الاستيراد
      if (importBinding != null) {
        final staff = await _staffDao.getStaffById(importBinding.staffId);
        if (staff == null) {
          checks.add(
            AttendanceFileIdCheck(
              externalId: externalId,
              status: AttendanceFileIdStatus.invalid,
              reason: 'الموظف المرتبط غير موجود في قاعدة البيانات',
              punchCount: count,
            ),
          );
        } else if (!staff.isActive || staff.status != 'active') {
          checks.add(
            AttendanceFileIdCheck(
              externalId: externalId,
              staffId: staff.staffId,
              staffName: staff.name,
              status: AttendanceFileIdStatus.invalid,
              reason: 'حالة الموظف: ${staff.status}',
              punchCount: count,
            ),
          );
        } else {
          checks.add(
            AttendanceFileIdCheck(
              externalId: externalId,
              staffId: staff.staffId,
              staffName: staff.name,
              status: AttendanceFileIdStatus.matched,
              punchCount: count,
              boundOnImportDevice: true,
            ),
          );
        }
        continue;
      }

      // 2) نفس البصمة مربوطة على أي جهاز حقيقي → نفس الموظف (بدون إنشاء)
      final otherMapping = await _deviceDao
          .getEnrolledMappingByExternalIdAnyDevice(
            externalId,
            excludeDeviceId: importDevice?.id,
          );
      if (otherMapping != null) {
        final staff = await _staffDao.getStaffById(otherMapping.staffId);
        if (staff == null) {
          checks.add(
            AttendanceFileIdCheck(
              externalId: externalId,
              status: AttendanceFileIdStatus.invalid,
              reason: 'الموظف المربوط بالبصمة غير موجود',
              punchCount: count,
            ),
          );
        } else if (!staff.isActive || staff.status != 'active') {
          checks.add(
            AttendanceFileIdCheck(
              externalId: externalId,
              staffId: staff.staffId,
              staffName: staff.name,
              status: AttendanceFileIdStatus.invalid,
              reason: 'حالة الموظف: ${staff.status}',
              punchCount: count,
            ),
          );
        } else {
          checks.add(
            AttendanceFileIdCheck(
              externalId: externalId,
              staffId: staff.staffId,
              staffName: staff.name,
              status: AttendanceFileIdStatus.matched,
              punchCount: count,
            ),
          );
        }
        continue;
      }

      // 3) الرقم معروف لكن الربط عليه غير enrolled (مرفوض/معلق/فشل)
      final otherRecords = await _deviceDao.getMappingsByExternalIdAnyDevice(
        externalId,
      );
      if (otherRecords.isNotEmpty) {
        checks.add(
          AttendanceFileIdCheck(
            externalId: externalId,
            status: AttendanceFileIdStatus.invalid,
            reason:
                'ربط البصمة بحالة "${otherRecords.first.enrollmentStatus}" — '
                'يحتاج إعادة تسجيل أو ربط يدوي',
            punchCount: count,
          ),
        );
        continue;
      }

      // 4) رقم مجهول — ما ينشئش موظف: تخطي + تقرير
      checks.add(
        AttendanceFileIdCheck(
          externalId: externalId,
          staffName: excelName,
          status: AttendanceFileIdStatus.unknown,
          reason: excelName == null
              ? 'لا يوجد موظف مربوط بهذا الرقم'
              : 'لا يوجد موظف مربوط بهذا الرقم (الاسم في الملف: $excelName)',
          punchCount: count,
        ),
      );
    }
    return checks;
  }

  BiffReadResult _readGridDetailed(Uint8List bytes, String ext) {
    if (ext == 'xlsx' || ext == 'xlsm') {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        return const BiffReadResult(
          grid: [],
          cellsRead: 0,
          warnings: [],
          sheetCount: 0,
        );
      }
      // أول شيت فيه بيانات
      for (final sheet in excel.tables.values) {
        final grid = <List<String>>[];
        for (final row in sheet.rows) {
          final cells = row.map(_cellToString).toList();
          while (cells.isNotEmpty && cells.last.isEmpty) {
            cells.removeLast();
          }
          if (cells.any((c) => c.isNotEmpty)) grid.add(cells);
        }
        if (grid.isNotEmpty) {
          return BiffReadResult(
            grid: grid,
            cellsRead: grid.fold(0, (sum, r) => sum + r.length),
            warnings: const [],
            sheetCount: 1,
          );
        }
      }
      return const BiffReadResult(
        grid: [],
        cellsRead: 0,
        warnings: [],
        sheetCount: 0,
      );
    }
    return LegacyExcelReader.readGridDetailed(bytes, ext);
  }

  String _cellToString(Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    if (v is DateTimeCellValue) {
      final dt = DateTime(
        v.year, v.month, v.day, v.hour, v.minute, v.second,
      );
      return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
          '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
    }
    if (v is DateCellValue) {
      return '${v.year}-${_two(v.month)}-${_two(v.day)}';
    }
    if (v is TimeCellValue) {
      return '${_two(v.hour)}:${_two(v.minute)}:${_two(v.second)}';
    }
    if (v is IntCellValue) return '${v.value}';
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.truncateToDouble() ? '${d.toInt()}' : '$d';
    }
    if (v is BoolCellValue) return v.value ? '1' : '0';
    if (v is TextCellValue) return v.value.text ?? '';
    return '';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  // ── اكتشاف الأعمدة ────────────────────────────────────────────

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-.]+'), '');

  static const _idHeaders = {
    'no', 'idnumber', 'id', 'userid', 'enrollno', 'pin',
    'الرقم', 'رقم', 'الكود', 'كود', 'رقمالموظف', 'رقمالبصمة', 'البصمة',
  };
  static const _nameHeaders = {'name', 'employeename', 'الاسم', 'اسم', 'اسماءالموظفين'};
  static const _dateHeaders = {
    'datetime', 'date/time', 'date', 'time', 'checktime',
    'التاريخ', 'الوقت', 'التاريخوالوقت', 'تاريخ', 'وقت', 'زمنالحضور',
  };
  static const _statusHeaders = {
    'status', 'state', 'type', 'inout', 'الحالة', 'الحاله', 'النوع',
  };
  static const _deptHeaders = {'department', 'dept', 'القسم', 'الادارة', 'الإدارة'};
  static const _cardHeaders = {'cardno', 'card', 'badge', 'الكارت', 'رقمالكارت', 'البطاقة'};
  static const _verifyHeaders = {'verifycode', 'verify', 'طريقةالتحقق', 'التحقق'};
  static const _locHeaders = {'locationid', 'location', 'الموقع', 'الفرع'};
  static const _workHeaders = {'workcode', 'work', 'كودالعمل'};

  _FileColumns? _detectColumns(List<List<String>> grid) {
    final scanRows = grid.length < 12 ? grid.length : 12;
    // 1) صف ترويسة صريح (عمودان معروفان على الأقل + عمود تاريخ)
    for (var r = 0; r < scanRows; r++) {
      final cols = _mapHeaderRow(grid[r]);
      if (cols != null) return cols.copyWithDataStart(r + 1);
    }
    // 2) بلا ترويسة: تخطيط ZK الافتراضي (اسم=1، رقم=2، تاريخ=3، حالة=4)
    for (var r = 0; r < scanRows; r++) {
      final row = grid[r];
      if (row.length >= 5 &&
          _parseDateTime(row.length > 3 ? row[3] : '', '') != null &&
          (row.length > 2 ? row[2].trim().isNotEmpty : false)) {
        return _FileColumns.zkPositional(dataStartRow: r);
      }
    }
    return null;
  }

  _FileColumns? _mapHeaderRow(List<String> row) {
    int? id, name, date, time, status, dept, card, verify, loc, work, idNum;
    var hits = 0;
    for (var c = 0; c < row.length; c++) {
      final n = _norm(row[c]);
      if (n.isEmpty) continue;
      if (_idHeaders.contains(n) && (id == null || n == 'no')) {
        id ??= c;
        hits++;
      } else if (_nameHeaders.contains(n) && name == null) {
        name = c;
        hits++;
      } else if (_dateHeaders.contains(n)) {
        if (n.contains('time') && !n.contains('date') ||
            n == 'الوقت' ||
            n == 'وقت' ||
            n == 'time') {
          time ??= c;
        } else {
          date ??= c;
        }
        hits++;
      } else if (_statusHeaders.contains(n) && status == null) {
        status = c;
        hits++;
      } else if (_deptHeaders.contains(n) && dept == null) {
        dept = c;
        hits++;
      } else if (_cardHeaders.contains(n) && card == null) {
        card = c;
        hits++;
      } else if (_verifyHeaders.contains(n) && verify == null) {
        verify = c;
        hits++;
      } else if (_locHeaders.contains(n) && loc == null) {
        loc = c;
        hits++;
      } else if (_workHeaders.contains(n) && work == null) {
        work = c;
        hits++;
      } else if (n == 'idnumber' && idNum == null) {
        idNum = c;
        hits++;
      }
    }
    if (hits >= 2 && date != null) {
      return _FileColumns(
        dataStartRow: 0,
        idCol: id ?? idNum ?? card ?? 2,
        nameCol: name,
        dateCol: date,
        timeCol: time,
        statusCol: status,
        deptCol: dept,
        cardCol: card,
        verifyCol: verify,
        locCol: loc,
        workCol: work,
        idNumberCol: idNum,
      );
    }
    return null;
  }

  // ── تحليل التاريخ والحالة ─────────────────────────────────────

  /// يقبل: 9/1/2026 3:14:40 PM (صيغة ZK) و yyyy-MM-dd HH:mm:ss وعمودين
  /// منفصلين للتاريخ والوقت، والتواريخ المسلسلة (Excel serial)، و yyyy/MM/dd.
  static DateTime? _parseDateTime(String dateRaw, String timeRaw) {
    var s = dateRaw.trim();
    final t = timeRaw.trim();
    if (s.isEmpty) return null;
    // رقم مسلسل لإكسل (أيام منذ 1899-12-30) — خلايا NUMBER/FORUMLA.
    // الحساب بـUTC عمداً لتفادي انزياح التوقيت الصيفي بين الأجهزة.
    final serial = double.tryParse(s);
    if (serial != null && t.isEmpty && serial >= 20000 && serial < 80000) {
      final base = DateTime.utc(1899, 12, 30);
      return base.add(Duration(
        days: serial.floor(),
        milliseconds: ((serial - serial.floor()) * 86400000).round(),
      ));
    }
    if (t.isNotEmpty &&
        !RegExp(r'[AP]\.?M\.?', caseSensitive: false).hasMatch(s)) {
      s = '$s $t';
    }
    // M/d/yyyy h:mm[:ss] [AM|PM]
    var m = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AP])\.?\s*M?\.?$',
      caseSensitive: false,
    ).firstMatch(s);
    m ??= RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(s);
    if (m != null) {
      try {
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        final year = int.parse(m.group(3)!);
        final month = a <= 12 ? a : b;
        final day = a <= 12 ? b : a;
        var hour = m.group(4) == null ? 0 : int.parse(m.group(4)!);
        final minute = m.group(5) == null ? 0 : int.parse(m.group(5)!);
        final second = m.group(6) == null ? 0 : int.parse(m.group(6)!);
        final ampm = m.groupCount >= 7 ? m.group(7) : null;
        if (ampm != null) {
          final isPm = ampm.toUpperCase() == 'P';
          if (isPm && hour < 12) hour += 12;
          if (!isPm && hour == 12) hour = 0;
        }
        return DateTime(year, month, day, hour, minute, second);
      } catch (_) {
        return null;
      }
    }
    // yyyy-MM-dd[ HH:mm[:ss]] أو yyyy/MM/dd[ HH:mm[:ss]]
    m = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(s);
    if (m != null) {
      try {
        return DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
          m.group(4) == null ? 0 : int.parse(m.group(4)!),
          m.group(5) == null ? 0 : int.parse(m.group(5)!),
          m.group(6) == null ? 0 : int.parse(m.group(6)!),
        );
      } catch (_) {
        return null;
      }
    }
    // dd-MM-yyyy[ HH:mm[:ss]]
    m = RegExp(
      r'^(\d{1,2})-(\d{1,2})-(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(s);
    if (m != null) {
      try {
        return DateTime(
          int.parse(m.group(3)!),
          int.parse(m.group(2)!),
          int.parse(m.group(1)!),
          m.group(4) == null ? 0 : int.parse(m.group(4)!),
          m.group(5) == null ? 0 : int.parse(m.group(5)!),
          m.group(6) == null ? 0 : int.parse(m.group(6)!),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _normalizeStatus(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'unknown';
    if (s.contains('out') || s.contains('خروج') || s.contains('انصراف')) {
      return 'check_out';
    }
    if (s.contains('in') ||
        s.contains('دخول') ||
        s.contains('حضور') ||
        s.contains('دوام')) {
      return 'check_in';
    }
    return 'unknown';
  }

  // ── التنفيذ في القاعدة ────────────────────────────────────────

  Future<BiometricDevice> _ensureImportDevice() async {
    final devices = await _deviceDao.getAllDevices();
    for (final d in devices) {
      if (d.deviceCode == importDeviceCode) return d;
    }
    final now = DateTime.now();
    final id = await _deviceDao.addDevice(
      BiometricDevicesCompanion.insert(
        deviceCode: importDeviceCode,
        name: importDeviceName,
        connectionType: 'file_import',
        vendor: const Value('ZKTeco'),
        // غير نشط عمداً: المزامنة التلقائية/الجماعية للأجهزة الحية فقط،
        // وجهاز الملف يُستخدم من زرار الاستيراد فقط.
        isActive: const Value(false),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final created = await _deviceDao.getDeviceById(id);
    if (created == null) throw StateError('تعذّر إنشاء جهاز الاستيراد');
    return created;
  }

  /// ينفّذ معاينة محللة: إدخال الأحداث الخام ثم نفس خط معالجة المزامنة.
  Future<AttendanceFileImportResult> importPunches(
    AttendanceFilePreview preview, {
    String triggeredBy = 'excel_import',
  }) async {
    if (preview.punches.isEmpty) {
      return const AttendanceFileImportResult(
        fetched: 0,
        matched: 0,
        unmatched: 0,
        duplicate: 0,
        newStaff: 0,
        renamed: 0,
        unmatchedSamples: [],
        errors: ['لا توجد بصمات صالحة للاستيراد'],
        error: 'لا توجد بصمات صالحة للاستيراد',
      );
    }

    // إعادة التحقق وقت التنفيذ (المستخدم ممكن يكون عدّل الربط في نصارح التأكيد)
    final checks = await _validateIds(preview.punches);
    final staffIdById = <String, String>{};
    for (final check in checks) {
      if (check.status == AttendanceFileIdStatus.matched &&
          check.staffId != null) {
        staffIdById[check.externalId] = check.staffId!;
      }
    }
    final importable = preview.punches
        .where((p) => staffIdById.containsKey(p.externalId))
        .toList();
    final unknownIds = checks
        .where((c) => c.status == AttendanceFileIdStatus.unknown)
        .map((c) => '${c.externalId} (${c.punchCount} بصمة)')
        .toList();
    final invalidIds = checks
        .where((c) => c.status == AttendanceFileIdStatus.invalid)
        .map((c) => '${c.externalId}${c.staffName == null ? '' : ' — ${c.staffName}'}'
            ': ${c.reason ?? 'غير صالح'}')
        .toList();
    final skippedUnknown = checks
        .where((c) => c.status == AttendanceFileIdStatus.unknown)
        .fold(0, (sum, c) => sum + c.punchCount);
    final skippedInvalid = checks
        .where((c) => c.status == AttendanceFileIdStatus.invalid)
        .fold(0, (sum, c) => sum + c.punchCount);

    if (importable.isEmpty) {
      return AttendanceFileImportResult(
        fetched: 0,
        matched: 0,
        unmatched: 0,
        duplicate: 0,
        newStaff: 0,
        renamed: 0,
        skippedUnknown: skippedUnknown,
        skippedInvalid: skippedInvalid,
        unknownIds: unknownIds,
        invalidIds: invalidIds,
        unmatchedSamples: const [],
        errors: const [
          'مفيش أي رقم بصمة في الملف مربوط بموظف — اتخطى الملف بالكامل',
        ],
        error: null,
      );
    }

    try {
      final device = await _ensureImportDevice();
      final batchId = 'file_${const Uuid().v4()}';
      var duplicate = 0;
      var linkedIds = 0;
      final staffCountBefore = (await _staffDao.getAllStaff()).length;

      // البصمات الموجودة مسبقاً لهذا الجهاز (insertOrIgnore لا يميّز
      // المكرر من قيمته الراجعة، لذا نفحص مسبقاً).
      final knownHashes = await _deviceDao.getDedupHashesForDevice(device.id);
      final seenInFile = <String>{};

      // أسماء الموظفين كما وردت في الملف (لتحسين أسماء المنشئين تلقائياً)
      final namesById = <String, String>{};
      for (final p in preview.punches) {
        if (p.name.trim().isNotEmpty) namesById.putIfAbsent(p.externalId, () => p.name.trim());
      }

      await _deviceDao.attachedDatabase.transaction(() async {
        // ربط كل ID مربوط فعلاً بنفس الموظف على جهاز الاستيراد، عشان خط
        // المعالجة يطابقه من غير ما يخلق موظف جديد. الربط موجود مسبقاً على
        // جهاز حقيقي فيبقى زي ما هو.
        for (final check in checks) {
          if (check.status != AttendanceFileIdStatus.matched) continue;
          if (check.boundOnImportDevice || check.staffId == null) continue;
          final existing = await _deviceDao.getMappingRecordByExternalId(
            device.id,
            check.externalId,
          );
          if (existing != null) continue;
          final now = DateTime.now();
          await _deviceDao.addMapping(
            StaffBiometricMappingsCompanion.insert(
              staffId: check.staffId!,
              deviceId: device.id,
              externalUserId: check.externalId,
              enrollmentStatus: 'enrolled',
              createdAt: now,
              updatedAt: now,
            ),
          );
          linkedIds++;
        }

        for (final punch in importable) {
          final hashStr =
              '${device.id}_${punch.externalId}_${punch.time.toIso8601String()}';
          final dedupHash = sha256.convert(utf8.encode(hashStr)).toString();
          if (knownHashes.contains(dedupHash) ||
              !seenInFile.add(dedupHash)) {
            duplicate++;
            continue;
          }
          final payload = jsonEncode({
            'source': 'excel_import',
            'file': preview.fileName,
            'name': punch.name,
            'status': punch.rawStatus,
            'verify': punch.verifyCode,
            'department': punch.department,
          });
          await _deviceDao.addRawEvent(
            AttendanceRawEventsCompanion.insert(
              deviceId: device.id,
              externalUserId: punch.externalId,
              eventTime: punch.time,
              eventType: Value(punch.eventType),
              rawPayload: Value(payload),
              syncBatchId: Value(batchId),
              dedupHash: dedupHash,
              status: 'pending',
              createdAt: DateTime.now(),
            ),
          );
          knownHashes.add(dedupHash);
        }
      });

      final processed = await _sync.processPendingEvents(device.id);

      // توليد الغياب للأيام المغلقة في نطاق الملف (لا يفشل الاستيراد).
      var absencesCreated = 0;
      if (processed.matched + processed.unmatched > 0 &&
          preview.minTime != null) {
        try {
          absencesCreated = await _sync.engine
              .generateAbsencesForRange(preview.minTime!, DateTime.now());
        } catch (_) {}
      }

      // لا إنشاء موظفين من الاستيراد: الربط بيتعمل على الموظف الموجود فقط،
      // فأي زيادة في عدد الموظفين تعني خلل في التحقق السابق.
      final afterStaff = await _staffDao.getAllStaff();
      final newStaff = (afterStaff.length - staffCountBefore).clamp(0, afterStaff.length);

      // عينات غير المطابقين من نفس الدفعة لعرضها للمستخدم
      final unmatchedSamples = <String>[];
      try {
        final unmatched = await _deviceDao.getUnmatchedEvents();
        for (final e in unmatched) {
          if (e.syncBatchId == batchId && unmatchedSamples.length < 20) {
            final label = namesById[e.externalUserId];
            unmatchedSamples.add(
              '${label == null || label.isEmpty ? 'بصمة ${e.externalUserId}' : label} — ${_fmtTime(e.eventTime)}${e.errorMessage == null ? '' : ' (${e.errorMessage})'}',
            );
          }
        }
      } catch (_) {}

      return AttendanceFileImportResult(
        fetched: importable.length,
        matched: processed.matched,
        unmatched: processed.unmatched,
        duplicate: duplicate,
        newStaff: newStaff,
        renamed: 0,
        linkedIds: linkedIds,
        skippedUnknown: skippedUnknown,
        skippedInvalid: skippedInvalid,
        absencesCreated: absencesCreated,
        unknownIds: unknownIds,
        invalidIds: invalidIds,
        unmatchedSamples: unmatchedSamples,
        errors: preview.errors,
        error: null,
      );
    } catch (e) {
      return AttendanceFileImportResult(
        fetched: 0,
        matched: 0,
        unmatched: 0,
        duplicate: 0,
        newStaff: 0,
        renamed: 0,
        skippedUnknown: skippedUnknown,
        skippedInvalid: skippedInvalid,
        unknownIds: unknownIds,
        invalidIds: invalidIds,
        unmatchedSamples: const [],
        errors: const [],
        error: 'فشل الاستيراد: $e',
      );
    }
  }

  static String _fmtTime(DateTime t) =>
      '${t.year}/${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _FileColumns {
  final int dataStartRow;
  final int idCol;
  final int? nameCol;
  final int dateCol;
  final int? timeCol;
  final int? statusCol;
  final int? deptCol;
  final int? cardCol;
  final int? verifyCol;
  final int? locCol;
  final int? workCol;
  final int? idNumberCol;

  const _FileColumns({
    required this.dataStartRow,
    required this.idCol,
    required this.nameCol,
    required this.dateCol,
    required this.timeCol,
    required this.statusCol,
    required this.deptCol,
    required this.cardCol,
    required this.verifyCol,
    required this.locCol,
    required this.workCol,
    required this.idNumberCol,
  });

  /// تخطيط ZK الافتراضي بلا ترويسة: قسم=0 اسم=1 رقم=2 تاريخ=3 حالة=4.
  factory _FileColumns.zkPositional({required int dataStartRow}) =>
      _FileColumns(
        dataStartRow: dataStartRow,
        idCol: 2,
        nameCol: 1,
        dateCol: 3,
        timeCol: null,
        statusCol: 4,
        deptCol: 0,
        cardCol: 9,
        verifyCol: 8,
        locCol: 5,
        workCol: 7,
        idNumberCol: 6,
      );

  _FileColumns copyWithDataStart(int row) => _FileColumns(
    dataStartRow: row,
    idCol: idCol,
    nameCol: nameCol,
    dateCol: dateCol,
    timeCol: timeCol,
    statusCol: statusCol,
    deptCol: deptCol,
    cardCol: cardCol,
    verifyCol: verifyCol,
    locCol: locCol,
    workCol: workCol,
    idNumberCol: idNumberCol,
  );
}
