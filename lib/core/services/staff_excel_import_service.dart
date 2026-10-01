import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:excel/excel.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// صف واحد مقروء من الإكسل بعد التحويل
class StaffExcelRow {
  final int excelRowNumber; // رقم الصف في الإكسل (1-based مع الهيدر)
  final String? staffIdRaw;
  final String name;
  final String position;
  final double basicSalary;
  final DateTime hireDate;
  final String externalId;
  final String? phone;
  final String? email;
  final String? nationalId;
  final String? department;
  final String? address;
  final String? employmentType;
  final Map<String, dynamic> raw;

  StaffExcelRow({
    required this.excelRowNumber,
    required this.staffIdRaw,
    required this.name,
    required this.position,
    required this.basicSalary,
    required this.hireDate,
    required this.externalId,
    this.phone,
    this.email,
    this.nationalId,
    this.department,
    this.address,
    this.employmentType,
    required this.raw,
  });
}

/// نتيجة التحقق لصف واحد
class StaffExcelRowValidation {
  final StaffExcelRow row;
  final bool isValid;
  final List<String> errors;
  final String? resolvedStaffId; // بعد التوليد لو فاضي
  final DateTime resolvedHireDate;

  StaffExcelRowValidation({
    required this.row,
    required this.isValid,
    required this.errors,
    this.resolvedStaffId,
    required this.resolvedHireDate,
  });
}

/// معاينة كاملة قبل الكتابة
class StaffExcelPreview {
  final List<StaffExcelRowValidation> rows;
  final List<String> fileErrors; // أخطاء عامة (ملف فاضي، هيدر ناقص...)

  StaffExcelPreview({required this.rows, this.fileErrors = const []});

  int get total => rows.length;
  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.where((r) => !r.isValid).length;
}

/// نتيجة الاستيراد الفعلي
class StaffExcelImportResult {
  final int addedStaff;
  final int addedMappings;
  final List<String> errors; // كل صف فشل + السبب
  final List<String> addedStaffIds;

  StaffExcelImportResult({
    required this.addedStaff,
    required this.addedMappings,
    required this.errors,
    required this.addedStaffIds,
  });
}

class StaffExcelImportService {
  final AppDatabase db;

  StaffExcelImportService(this.db);

  // خريطة أسماء الأعمدة المتوقعة (lowercase trimmed) → الحقل الداخلي
  static const _headerAliases = <String, String>{
    'staffid': 'staffId',
    'staff_id': 'staffId',
    'كود الموظف': 'staffId',
    'كود': 'staffId',
    'name': 'name',
    'الاسم': 'name',
    'اسم الموظف': 'name',
    'position': 'position',
    'الوظيفة': 'position',
    'المسمى الوظيفي': 'position',
    'basicsalary': 'basicSalary',
    'basic_salary': 'basicSalary',
    'المرتب': 'basicSalary',
    'المرتب الأساسي': 'basicSalary',
    'الراتب': 'basicSalary',
    'hiredate': 'hireDate',
    'hire_date': 'hireDate',
    'تاريخ التعيين': 'hireDate',
    'تاريخ التوظيف': 'hireDate',
    'externalid': 'externalId',
    'external_id': 'externalId',
    'fingerprint': 'externalId',
    'رقم البصمة': 'externalId',
    'البصمة': 'externalId',
    'بصمة': 'externalId',
    'phone': 'phone',
    'التليفون': 'phone',
    'هاتف': 'phone',
    'email': 'email',
    'البريد': 'email',
    'nationalid': 'nationalId',
    'national_id': 'nationalId',
    'الرقم القومي': 'nationalId',
    'department': 'department',
    'القسم': 'department',
    'address': 'address',
    'العنوان': 'address',
    'employmenttype': 'employmentType',
    'نوع التوظيف': 'employmentType',
  };

  String _normalizeHeader(String h) {
    return h.trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  }

  String _cellString(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final v = cell.value;
    if (v is DateTime) return (v as DateTime).toIso8601String().split('T').first;
    return v.toString().trim();
  }

  double? _parseSalary(String s) {
    if (s.isEmpty) return null;
    final cleaned = s.replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(cleaned);
  }

  DateTime? _parseHireDate(Data? cell, String str) {
    if (cell != null && cell.value is DateTime) {
      final dt = cell.value as DateTime;
      return DateTime(dt.year, dt.month, dt.day);
    }
    if (str.isEmpty) return null;
    // جرب صيغ شائعة
    for (final fmt in ['yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy/MM/dd']) {
      try {
        final parts = str.split(RegExp(r'[-/]'));
        if (parts.length == 3) {
          int y, m, d;
          if (fmt.startsWith('yyyy')) {
            y = int.parse(parts[0]); m = int.parse(parts[1]); d = int.parse(parts[2]);
          } else if (fmt == 'dd/MM/yyyy') {
            d = int.parse(parts[0]); m = int.parse(parts[1]); y = int.parse(parts[2]);
          } else {
            m = int.parse(parts[0]); d = int.parse(parts[1]); y = int.parse(parts[2]);
          }
          return DateTime(y, m, d);
        }
      } catch (_) {}
    }
    return DateTime.tryParse(str);
  }

  Future<String> _generateStaffId() async {
    final all = await db.staffManagementDao.getAllStaff();
    int maxId = 0;
    for (final s in all) {
      final n = int.tryParse(s.staffId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (n > maxId) maxId = n;
    }
    return 'STAFF${(maxId + 1).toString().padLeft(4, '0')}';
  }

  /// قراءة + تحقق بدون كتابة (dry-run)
  Future<StaffExcelPreview> preview(String filePath, {required int deviceId}) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return StaffExcelPreview(rows: [], fileErrors: ['الملف لا يحتوي على أي شيت']);
    }
    // استخدم أول شيت فيه بيانات
    Sheet? sheet;
    for (final t in excel.tables.values) {
      if (t.rows.isNotEmpty) { sheet = t; break; }
    }
    if (sheet == null || sheet.rows.isEmpty) {
      return StaffExcelPreview(rows: [], fileErrors: ['الشيت فاضي']);
    }

    final headerRow = sheet.rows.first;
    final headerMap = <int, String>{};
    for (int i = 0; i < headerRow.length; i++) {
      final h = _cellString(headerRow[i]);
      if (h.isEmpty) continue;
      final norm = _normalizeHeader(h);
      final mapped = _headerAliases[norm] ?? _headerAliases[h.toLowerCase().trim()] ?? h;
      // خزّن بالاسم المعياري
      final key = _headerAliases[norm] ?? norm;
      // نحاول نطابق norm مع aliases
      String? canonical;
      for (final e in _headerAliases.entries) {
        if (_normalizeHeader(e.key) == norm) { canonical = e.value; break; }
      }
      headerMap[i] = canonical ?? h;
    }

    // تحقق هيدر إجباري
    final needed = ['name', 'position', 'basicSalary', 'externalId'];
    final found = headerMap.values.toSet();
    final missing = needed.where((n) => !found.contains(n)).toList();
    if (missing.isNotEmpty) {
      return StaffExcelPreview(rows: [], fileErrors: ['أعمدة إجبارية ناقصة في الهيدر: ${missing.join(', ')} — الأعمدة المطلوبة: الاسم، الوظيفة، المرتب الأساسي، رقم البصمة']);
    }

    // فهرس كل عمود
    int idxOf(String canonical) {
      for (final e in headerMap.entries) {
        if (e.value == canonical) return e.key;
      }
      return -1;
    }

    final idxStaffId = idxOf('staffId');
    final idxName = idxOf('name');
    final idxPosition = idxOf('position');
    final idxSalary = idxOf('basicSalary');
    final idxHireDate = idxOf('hireDate');
    final idxExternal = idxOf('externalId');
    final idxPhone = idxOf('phone');
    final idxEmail = idxOf('email');
    final idxNational = idxOf('nationalId');
    final idxDept = idxOf('department');
    final idxAddress = idxOf('address');
    final idxEmpType = idxOf('employmentType');

    // جهّز بيانات موجودة مسبقاً للتحقق
    final existingStaffIds = (await db.staffManagementDao.getAllStaff()).map((s) => s.staffId).toSet();
    final existingExternalForDevice = (await db.attendanceDeviceDao.getMappingsForDevice(deviceId)).map((m) => m.externalUserId).toSet();

    final seenExternalInFile = <String>{};
    final seenStaffIdInFile = <String>{};
    final validations = <StaffExcelRowValidation>[];

    for (int r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      String getCell(int idx) => idx >= 0 && idx < row.length ? _cellString(row[idx]) : '';
      Data? getCellData(int idx) => idx >= 0 && idx < row.length ? row[idx] : null;

      final staffIdRaw = getCell(idxStaffId);
      final name = getCell(idxName);
      final position = getCell(idxPosition);
      final salaryStr = getCell(idxSalary);
      final hireStr = getCell(idxHireDate);
      final hireCell = getCellData(idxHireDate);
      final externalId = getCell(idxExternal);
      final phone = getCell(idxPhone);
      final email = getCell(idxEmail);
      final nationalId = getCell(idxNational);
      final department = getCell(idxDept);
      final address = getCell(idxAddress);
      final empType = getCell(idxEmpType);

      final errors = <String>[];
      if (name.isEmpty) errors.add('الاسم إجباري');
      if (position.isEmpty) errors.add('الوظيفة إجبارية');
      final salary = _parseSalary(salaryStr);
      if (salary == null) errors.add('المرتب الأساسي إجباري ورقم صحيح');
      if (externalId.isEmpty) errors.add('رقم البصمة إجباري');
      DateTime? hireDate = _parseHireDate(hireCell, hireStr);
      final resolvedHireDate = hireDate ?? DateTime.now();
      // لو staffId موجود في الملف مكرر
      if (staffIdRaw.isNotEmpty) {
        if (seenStaffIdInFile.contains(staffIdRaw)) errors.add('كود الموظف مكرر داخل الملف: $staffIdRaw');
        if (existingStaffIds.contains(staffIdRaw)) errors.add('كود الموظف موجود مسبقاً في النظام: $staffIdRaw');
      }
      if (externalId.isNotEmpty) {
        if (seenExternalInFile.contains(externalId)) errors.add('رقم البصمة مكرر داخل الملف: $externalId');
        if (existingExternalForDevice.contains(externalId)) errors.add('رقم البصمة موجود مسبقاً لنفس الجهاز: $externalId');
      }
      // سجّل seen حتى لو فيه خطأ عشان نكشف التكرار اللاحق
      if (externalId.isNotEmpty) seenExternalInFile.add(externalId);
      if (staffIdRaw.isNotEmpty) seenStaffIdInFile.add(staffIdRaw);

      // توليد staffId لو فاضي (للعرض فقط، التوليد الحقيقي عند الاستيراد قد يختلف لو اتضاف صفوف قبله)
      String? resolvedStaffId;
      if (staffIdRaw.isNotEmpty) {
        resolvedStaffId = staffIdRaw;
      } else if (errors.isEmpty) {
        // معاينة: نعرض STAFF#### متوقع (تقريبي)
        resolvedStaffId = null; // سيتولد عند الاستيراد
      }

      final rowObj = StaffExcelRow(
        excelRowNumber: r + 1,
        staffIdRaw: staffIdRaw.isEmpty ? null : staffIdRaw,
        name: name,
        position: position,
        basicSalary: salary ?? 0,
        hireDate: resolvedHireDate,
        externalId: externalId,
        phone: phone.isEmpty ? null : phone,
        email: email.isEmpty ? null : email,
        nationalId: nationalId.isEmpty ? null : nationalId,
        department: department.isEmpty ? null : department,
        address: address.isEmpty ? null : address,
        employmentType: empType.isEmpty ? null : empType,
        raw: {'row': row.map((c) => c?.value).toList()},
      );

      validations.add(StaffExcelRowValidation(
        row: rowObj,
        isValid: errors.isEmpty,
        errors: errors,
        resolvedStaffId: resolvedStaffId,
        resolvedHireDate: resolvedHireDate,
      ));
    }

    // لو كل الصفوف فاضية (مثلاً صفوف فارغة في الآخر) احذفها
    final nonEmpty = validations.where((v) => v.row.name.isNotEmpty || v.row.externalId.isNotEmpty || v.row.position.isNotEmpty).toList();
    return StaffExcelPreview(rows: nonEmpty);
  }

  /// تنفيذ الاستيراد الفعلي — يكتب فقط الصفوف الصالحة حسب نفس قواعد preview
  Future<StaffExcelImportResult> import(StaffExcelPreview preview, {required int deviceId}) async {
    int addedStaff = 0;
    int addedMappings = 0;
    final errors = <String>[];
    final addedIds = <String>[];

    // أعد التحقق من التكرارات داخل preview نفسه (حماية إضافية)
    final existingStaffIds = (await db.staffManagementDao.getAllStaff()).map((s) => s.staffId).toSet();
    final existingExternalForDevice = (await db.attendanceDeviceDao.getMappingsForDevice(deviceId)).map((m) => m.externalUserId).toSet();
    final seenExternal = <String>{};
    final seenStaff = <String>{};

    for (final v in preview.rows) {
      if (!v.isValid) {
        errors.add('صف ${v.row.excelRowNumber}: ${v.errors.join('، ')} — لم يتم استيراده');
        continue;
      }
      final row = v.row;
      // تحقق لحظي قبل الكتابة (حماية من سباق)
      if (row.externalId.isEmpty) {
        errors.add('صف ${row.excelRowNumber}: رقم البصمة فاضي');
        continue;
      }
      if (seenExternal.contains(row.externalId) || existingExternalForDevice.contains(row.externalId)) {
        errors.add('صف ${row.excelRowNumber}: رقم البصمة ${row.externalId} مكرر — لم يتم استيراده');
        continue;
      }
      String staffId = row.staffIdRaw ?? '';
      if (staffId.isEmpty) {
        staffId = await _generateStaffId();
        // تأكد ما اتكررش في نفس الاستيراد
        while (existingStaffIds.contains(staffId) || seenStaff.contains(staffId)) {
          staffId = await _generateStaffId();
        }
      } else {
        if (existingStaffIds.contains(staffId) || seenStaff.contains(staffId)) {
          errors.add('صف ${row.excelRowNumber}: كود الموظف $staffId موجود مسبقاً — لم يتم استيراده');
          continue;
        }
      }

      try {
        final now = DateTime.now();
        await db.staffManagementDao.addStaff(StaffTableCompanion.insert(
          staffId: staffId,
          name: row.name,
          position: row.position,
          employmentType: row.employmentType?.isNotEmpty == true ? row.employmentType! : 'full_time',
          basicSalary: row.basicSalary,
          hireDate: row.hireDate,
          status: 'active',
          nationalId: Value(row.nationalId),
          phone: Value(row.phone),
          email: Value(row.email),
          address: Value(row.address),
          department: Value(row.department),
          createdAt: now,
          updatedAt: now,
        ));
        addedStaff++;
        existingStaffIds.add(staffId);
        seenStaff.add(staffId);
        addedIds.add(staffId);
      } catch (e) {
        errors.add('صف ${row.excelRowNumber}: فشل إضافة الموظف $staffId — $e');
        continue;
      }

      try {
        final now = DateTime.now();
        await db.attendanceDeviceDao.addMapping(StaffBiometricMappingsCompanion.insert(
          staffId: staffId,
          deviceId: deviceId,
          externalUserId: row.externalId,
          enrollmentStatus: 'enrolled',
          enrolledAt: Value(now),
          createdAt: now,
          updatedAt: now,
        ));
        addedMappings++;
        existingExternalForDevice.add(row.externalId);
        seenExternal.add(row.externalId);
      } catch (e) {
        errors.add('صف ${row.excelRowNumber}: الموظف $staffId اتضاف لكن ربط البصمة ${row.externalId} فشل — $e (راجع يدوياً من إدارة البصمة)');
        // لا نحذف الموظف — نوضح في التقرير
      }
    }

    return StaffExcelImportResult(
      addedStaff: addedStaff,
      addedMappings: addedMappings,
      errors: errors,
      addedStaffIds: addedIds,
    );
  }
}
