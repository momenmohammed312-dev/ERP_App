import 'package:excel/excel.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/database/app_database.dart';

class SheetMatch {
  final String sheetName;
  final String trimmedName;
  final Staff? staff;
  SheetMatch({required this.sheetName, required this.trimmedName, required this.staff});
  bool get matched => staff != null;
}

class RowParseResult {
  final int rowIndex;
  final DateTime? date;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final double? workingHours;
  final String status;
  final String? error;
  final String rawPresence;
  final String rawCheckout;
  RowParseResult({required this.rowIndex, required this.date, required this.checkInTime, required this.checkOutTime, required this.workingHours, required this.status, required this.error, required this.rawPresence, required this.rawCheckout});
}

class SheetImportReport {
  final String sheetName;
  final Staff? staff;
  final int imported;
  final int skippedExists;
  final int conflicts;
  final int parseErrors;
  final List<String> errors;
  SheetImportReport({required this.sheetName, required this.staff, required this.imported, required this.skippedExists, required this.conflicts, required this.parseErrors, required this.errors});
}

class _ParsedTime {
  final int? h;
  final int? m;
  final int? s;
  final String? error;
  final bool isAbsent;
  const _ParsedTime({this.h, this.m, this.s, this.error, required this.isAbsent});
  bool get hasTime => h != null && m != null;
}

class HistoricalAttendanceImportService {
  final AppDatabase db;
  HistoricalAttendanceImportService(this.db);

  Map<String, Staff?> matchSheetsToStaff(List<String> sheetNames, List<Staff> staffList) {
    final map = <String, Staff>{};
    for (final s in staffList) {
      map[s.name.trim()] = s;
    }
    final result = <String, Staff?>{};
    for (final sheet in sheetNames) {
      final trimmed = sheet.trim();
      result[sheet] = map[trimmed];
    }
    return result;
  }

  _ParsedTime _parseExcelTime(dynamic value) {
    if (value == null) return const _ParsedTime(isAbsent: true);
    if (value is DateTime) {
      return _ParsedTime(h: value.hour, m: value.minute, s: value.second, isAbsent: false);
    }
    if (value is double) {
      final totalSeconds = (value * 24 * 3600).round();
      final h = (totalSeconds ~/ 3600) % 24;
      final m = (totalSeconds % 3600) ~/ 60;
      final s = totalSeconds % 60;
      return _ParsedTime(h: h, m: m, s: s, isAbsent: false);
    }
    String str = value.toString().trim();
    if (str.isEmpty || str == 'None' || str == 'null') return const _ParsedTime(isAbsent: true);
    if (str.contains('غ')) return const _ParsedTime(isAbsent: true);
    str = str.replaceAll(';', ':').replaceAll('؛', ':').trim();
    if (str.isEmpty) return const _ParsedTime(isAbsent: true);
    final parts = str.split(':');
    if (parts.length == 2 || parts.length == 3) {
      final h = int.tryParse(parts[0].trim());
      final m = int.tryParse(parts[1].trim());
      final s = parts.length == 3 ? int.tryParse(parts[2].trim()) ?? 0 : 0;
      if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60 && s >= 0 && s < 60) {
        return _ParsedTime(h: h, m: m, s: s, isAbsent: false);
      }
    }
    if (parts.length == 1) {
      final h = int.tryParse(parts[0].trim());
      if (h != null && h >= 0 && h < 24) return _ParsedTime(h: h, m: 0, s: 0, isAbsent: false);
    }
    return _ParsedTime(error: 'صيغة وقت غير مفهومة: $str', isAbsent: false);
  }

  DateTime? parseDateCell(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    try {
      final dt = DateTime.parse(str);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {}
    try {
      final normalized = str.replaceAll('/', '-');
      final dt = DateTime.parse(normalized);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {}
    return null;
  }

  List<RowParseResult> parseSheetRows(Sheet sheet) {
    final results = <RowParseResult>[];
    DateTime? lastValidDate;
    // كل صف قد يحتوي على بلوكين: يسار (0,2,3) ويمين (7,9,10)
    RowParseResult? parseBlock(dynamic dateVal, dynamic presVal, dynamic outVal, int excelRow) {
      final p = _parseExcelTime(presVal);
      final q = _parseExcelTime(outVal);
      DateTime? date = parseDateCell(dateVal);
      if (date == null) {
        final isHeader = dateVal?.toString().contains('التاريخ') == true;
        if (isHeader) return null;
        if ((presVal == null || presVal.toString().trim().isEmpty) && (outVal == null || outVal.toString().trim().isEmpty) && dateVal == null) return null;
        if ((p.hasTime || q.hasTime) && lastValidDate != null) {
          date = lastValidDate!.add(const Duration(days: 1));
        } else {
          // صف رأسي أو فاضي - تجاهل
          final allEmpty = (dateVal == null || dateVal.toString().trim().isEmpty) && (presVal == null || presVal.toString().trim().isEmpty) && (outVal == null || outVal.toString().trim().isEmpty);
          if (allEmpty) return null;
          // لو تاريخ غير صالح وليس رأس - سجل خطأ لكن لا تكسر
          return RowParseResult(rowIndex: excelRow, date: null, checkInTime: null, checkOutTime: null, workingHours: null, status: 'absent', error: 'تاريخ غير صالح: $dateVal', rawPresence: presVal?.toString() ?? '', rawCheckout: outVal?.toString() ?? '');
        }
      }
      lastValidDate = date;
      String? error;
      if (p.error != null) error = 'حضور: ${p.error}';
      if (q.error != null) error = error == null ? 'انصراف: ${q.error}' : '$error | انصراف: ${q.error}';
      DateTime? checkIn;
      DateTime? checkOut;
      if (p.hasTime) checkIn = DateTime(date.year, date.month, date.day, p.h!, p.m!, p.s ?? 0);
      if (q.hasTime) {
        int h = q.h!;
        if (h >= 1 && h <= 11) h += 12;
        checkOut = DateTime(date.year, date.month, date.day, h, q.m!, q.s ?? 0);
      }
      String status = 'present';
      if (p.isAbsent && q.isAbsent) status = 'absent';
      double? workingHours;
      if (checkIn != null && checkOut != null) {
        final diff = checkOut.difference(checkIn).inMinutes / 60.0;
        if (diff >= 0 && diff < 24) workingHours = diff;
      }
      return RowParseResult(rowIndex: excelRow, date: date, checkInTime: checkIn, checkOutTime: checkOut, workingHours: workingHours, status: status, error: error, rawPresence: presVal?.toString() ?? '', rawCheckout: outVal?.toString() ?? '');
    }

    for (int i = 2; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      // تحقق هل الصف كله فاضي
      final allEmpty = row.every((c) => c == null || c.value == null || c.value.toString().trim().isEmpty);
      if (allEmpty) continue;
      // تحقق هل هو صف رأس مكرر
      final firstStr = row.isNotEmpty ? row[0]?.value?.toString() ?? '' : '';
      if (firstStr.contains('التاريخ')) continue;
      // بلوك يسار
      final left = parseBlock(row.isNotEmpty ? row[0]?.value : null, row.length > 2 ? row[2]?.value : null, row.length > 3 ? row[3]?.value : null, i + 1);
      if (left != null) results.add(left);
      // بلوك يمين (إن وجد)
      if (row.length > 7) {
        final dateVal2 = row[7]?.value;
        final pres2 = row.length > 9 ? row[9]?.value : null;
        final out2 = row.length > 10 ? row[10]?.value : null;
        // تجاهل بلوك يمين فاضي تماما
        if (dateVal2 != null || pres2 != null || out2 != null) {
          final right = parseBlock(dateVal2, pres2, out2, i + 1);
          if (right != null) results.add(right);
        }
      }
    }
    return results;
  }

  Future<SheetImportReport> importSheet(String sheetName, Staff staff, List<RowParseResult> rows) async {
    int imported = 0;
    int skipped = 0;
    int conflicts = 0;
    int parseErrors = 0;
    final errors = <String>[];

    for (final r in rows) {
      if (r.date == null) {
        parseErrors++;
        errors.add('صف ${r.rowIndex}: ${r.error}');
        continue;
      }
      if (r.error != null) {
        parseErrors++;
        errors.add('صف ${r.rowIndex} (${r.date}): ${r.error}');
        continue;
      }
      final dateOnly = DateTime(r.date!.year, r.date!.month, r.date!.day);
      final existing = await (db.select(db.attendanceTable)
            ..where((a) => a.staffId.equals(staff.staffId) & a.date.equals(dateOnly)))
          .get();
      if (existing.isNotEmpty) {
        final hasImport = existing.any((e) => e.source == 'import');
        if (hasImport) {
          skipped++;
        } else {
          conflicts++;
          errors.add('صف ${r.rowIndex} (${r.date}): تعارض — يوجد سجل حضور مصدره ${existing.first.source} لنفس التاريخ');
        }
        continue;
      }

      await db.into(db.attendanceTable).insert(AttendanceTableCompanion.insert(
        staffId: staff.staffId,
        date: dateOnly,
        status: r.status,
        checkInTime: drift.Value(r.checkInTime),
        checkOutTime: drift.Value(r.checkOutTime),
        workingHours: drift.Value(r.workingHours),
        source: const drift.Value('import'),
        notes: const drift.Value('مستورد من ملف تاريخي - أغسطس 2026'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      imported++;
    }
    return SheetImportReport(sheetName: sheetName, staff: staff, imported: imported, skippedExists: skipped, conflicts: conflicts, parseErrors: parseErrors, errors: errors);
  }

  Future<List<SheetImportReport>> importFromExcel(Excel excel) async {
    final staffList = await db.staffManagementDao.getAllStaff();
    final sheetNames = excel.tables.keys.toList();
    final match = matchSheetsToStaff(sheetNames, staffList);
    final reports = <SheetImportReport>[];
    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      final sheet = entry.value;
      final staff = match[sheetName];
      if (staff == null) {
        reports.add(SheetImportReport(sheetName: sheetName, staff: null, imported: 0, skippedExists: 0, conflicts: 0, parseErrors: 0, errors: ['شيت مرفوض — لا يوجد موظف اسمه "$sheetName" بعد التنظيف']));
        continue;
      }
      final rows = parseSheetRows(sheet);
      final rep = await importSheet(sheetName, staff, rows);
      reports.add(rep);
    }
    return reports;
  }
}
