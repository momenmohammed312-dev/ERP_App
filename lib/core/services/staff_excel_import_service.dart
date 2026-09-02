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

/// صف في وضع التصحيح (تحديث كود البصمة بالاسم)
class StaffExcelCorrectionItem {
  final StaffExcelRow row;
  final String normalizedName;
  final Staff? matchedStaff;
  final List<StaffBiometricMapping> currentMappings;
  final List<String> errors;
  final bool isValid;
  final String action; // update | create | no_change | skip
  final bool willCreate;
  StaffExcelCorrectionItem({
    required this.row,
    required this.normalizedName,
    required this.matchedStaff,
    required this.currentMappings,
    required this.errors,
    required this.isValid,
    required this.action,
    this.willCreate = false,
  });
}

class StaffExcelCorrectionPreview {
  final List<StaffExcelCorrectionItem> items;
  final List<String> fileErrors;
  StaffExcelCorrectionPreview({required this.items, this.fileErrors = const []});
  int get total => items.length;
  int get updateCount => items.where((e) => e.action == 'update' && e.isValid).length;
  int get createCount => items.where((e) => e.action == 'create' && e.isValid).length;
  int get noChangeCount => items.where((e) => e.action == 'no_change').length;
  int get invalidCount => items.where((e) => !e.isValid).length;
}

class StaffExcelCorrectionResult {
  final int updated;
  final int created;
  final int skipped;
  final List<String> errors;
  StaffExcelCorrectionResult({required this.updated, required this.created, required this.skipped, required this.errors});
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
    'كود البصمة': 'externalId',
    'كود البصمة (id)': 'externalId',
    'كودالبصمة(id)': 'externalId',
    'كودالبصمة': 'externalId',
    'idالبصمة': 'externalId',
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
  // ── Correction mode (update by name) ──────────────────────────────────

  String _normalizeName(String s) {
    // إزالة المسافات الزيادة + lowercase + توحيد الألف والياء
    var n = s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    n = n.replaceAll(RegExp(r'[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    return n;
  }

  /// معاينة وضع التصحيح — المطابقة بالاسم فقط، تحديث كود البصمة بدون حذف حضور
  Future<StaffExcelCorrectionPreview> previewCorrection(String filePath, {required int deviceId}) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return StaffExcelCorrectionPreview(items: [], fileErrors: ['الملف لا يحتوي على أي شيت']);
    Sheet? sheet;
    for (final t in excel.tables.values) { if (t.rows.isNotEmpty) { sheet = t; break; } }
    if (sheet == null || sheet.rows.isEmpty) return StaffExcelCorrectionPreview(items: [], fileErrors: ['الشيت فاضي']);

    final headerRow = sheet.rows.first;
    final headerMap = <int, String>{};
    for (int i = 0; i < headerRow.length; i++) {
      final h = _cellString(headerRow[i]);
      if (h.isEmpty) continue;
      final norm = _normalizeHeader(h);
      String? canonical;
      for (final e in _headerAliases.entries) { if (_normalizeHeader(e.key) == norm) { canonical = e.value; break; } }
      headerMap[i] = canonical ?? h;
    }
    final found = headerMap.values.toSet();
    // للتصحيح يكفي الاسم + رقم البصمة
    final missing = <String>[];
    if (!found.contains('name')) missing.add('اسم الموظف');
    if (!found.contains('externalId')) missing.add('رقم البصمة');
    if (missing.isNotEmpty) return StaffExcelCorrectionPreview(items: [], fileErrors: ['أعمدة ناقصة: ${missing.join(', ')}']);

    int idxOf(String c) { for (final e in headerMap.entries) if (e.value == c) return e.key; return -1; }
    final idxName = idxOf('name');
    final idxExternal = idxOf('externalId');
    final idxPosition = idxOf('position');
    final idxSalary = idxOf('basicSalary');

    final allStaff = await db.staffManagementDao.getAllStaff();
    final allMappings = await db.attendanceDeviceDao.getAllMappings();
    final deviceMappings = allMappings.where((m) => m.deviceId == deviceId).toList();
    // خريطة اسم مطبع -> Staff
    final nameToStaff = <String, Staff>{};
    for (final s in allStaff) { nameToStaff[_normalizeName(s.name)] = s; }
    // existing externalId -> mapping (للجهاز المختار)
    final externalToMapping = {for (final m in deviceMappings) m.externalUserId: m};

    final seenNamesInFile = <String>{};
    final seenExternalInFile = <String>{};
    final items = <StaffExcelCorrectionItem>[];

    for (int r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      String getCell(int idx) => idx >= 0 && idx < row.length ? _cellString(row[idx]) : '';
      final name = getCell(idxName).trim();
      final externalId = getCell(idxExternal).trim();
      final position = idxPosition >=0 ? getCell(idxPosition).trim() : '';
      final salaryStr = idxSalary >=0 ? getCell(idxSalary).trim() : '';
      if (name.isEmpty && externalId.isEmpty && position.isEmpty && salaryStr.isEmpty) continue; // تجاهل صفوف فاضية
      // فلترة صفوف القمامة مثل Sheet26 بدون كود بصمة رقمي
      final errors = <String>[];
      if (name.isEmpty) errors.add('الاسم فاضي');
      if (externalId.isEmpty) errors.add('كود البصمة فاضي');
      final normName = _normalizeName(name);
      if (normName.isNotEmpty) {
        if (seenNamesInFile.contains(normName)) errors.add('الاسم مكرر داخل الملف');
        else seenNamesInFile.add(normName);
      }
      if (externalId.isNotEmpty) {
        if (seenExternalInFile.contains(externalId)) errors.add('كود البصمة مكرر داخل الملف: $externalId');
        else seenExternalInFile.add(externalId);
      }
      final matched = normName.isEmpty ? null : nameToStaff[normName];
      List<StaffBiometricMapping> currentMappings = [];
      if (matched != null) currentMappings = deviceMappings.where((m) => m.staffId == matched.staffId).toList();
      String action;
      if (matched == null) { action = 'create'; if (errors.isEmpty) errors.add('الاسم غير موجود — سيتم إنشاؤه كموظف جديد'); }
      else if (currentMappings.length == 1 && currentMappings.first.externalUserId == externalId) { action = 'no_change'; }
      else { action = 'update'; }
      // لو الكود الجديد مملوك لموظف آخر سيتم نقله تلقائياً (لا نمنع)
      final salary = _parseSalary(salaryStr);
      final rowObj = StaffExcelRow(
        excelRowNumber: r + 1, staffIdRaw: matched?.staffId, name: name, position: position,
        basicSalary: salary ?? 0, hireDate: matched?.hireDate ?? DateTime.now(),
        externalId: externalId, raw: {'row': row.map((c) => c?.value).toList()},
      );
      final isValid = errors.isEmpty || (errors.length == 1 && errors.first.contains('سيتم إنشاؤه'));
      // للتصحيح نعتبر create كـ valid أيضاً (سيعمل إنشاء)
      final hasOnlyCreateNote = errors.length == 1 && errors.first.contains('سيتم إنشاؤه');
      items.add(StaffExcelCorrectionItem(
        row: rowObj, normalizedName: normName, matchedStaff: matched,
        currentMappings: currentMappings, errors: hasOnlyCreateNote ? [] : errors,
        isValid: hasOnlyCreateNote ? true : errors.isEmpty, action: hasOnlyCreateNote ? 'create' : action,
        willCreate: hasOnlyCreateNote,
      ));
    }
    return StaffExcelCorrectionPreview(items: items);
  }

  Future<StaffExcelCorrectionResult> importCorrection(StaffExcelCorrectionPreview preview, {required int deviceId}) async {
    int updated = 0, created = 0, skipped = 0;
    final errors = <String>[];
    final allStaff = await db.staffManagementDao.getAllStaff();
    final staffById = {for (final s in allStaff) s.staffId: s};
    for (final item in preview.items) {
      if (!item.isValid) { skipped++; errors.add('صف ${item.row.excelRowNumber} (${item.row.name}): ${item.errors.join('، ')} — تم التخطي'); continue; }
      if (item.action == 'no_change') { skipped++; continue; }
      final newExternalId = item.row.externalId.trim();
      if (newExternalId.isEmpty) { errors.add('صف ${item.row.excelRowNumber}: كود البصمة فاضي'); skipped++; continue; }
      try {
        if (item.action == 'create' || item.matchedStaff == null) {
          // إنشاء موظف جديد + mapping
          String staffId = 'STAFF${DateTime.now().millisecondsSinceEpoch}${item.row.excelRowNumber}';
          // توليد آمن
          staffId = await _generateStaffId();
          final now = DateTime.now();
          final pos = item.row.position.isEmpty ? 'موظف' : item.row.position;
          final sal = item.row.basicSalary;
          await db.staffManagementDao.addStaff(StaffTableCompanion.insert(
            staffId: staffId, name: item.row.name, position: pos,
            employmentType: 'full_time', basicSalary: sal, hireDate: now, status: 'active',
            createdAt: now, updatedAt: now,
          ));
          await db.attendanceDeviceDao.addMapping(StaffBiometricMappingsCompanion.insert(
            staffId: staffId, deviceId: deviceId, externalUserId: newExternalId,
            enrollmentStatus: 'enrolled', enrolledAt: Value(now), createdAt: now, updatedAt: now,
          ));
          created++;
        } else {
          // تحديث: احذف كل mappings القديمة لهذا الموظف على نفس الجهاز + أي mapping يملك نفس externalId لموظف آخر
          final staffId = item.matchedStaff!.staffId;
          final existingForStaff = await db.attendanceDeviceDao.getMappingsForStaff(staffId);
          for (final m in existingForStaff.where((m) => m.deviceId == deviceId)) {
            await db.attendanceDeviceDao.deleteMapping(m.id);
          }
          // حرر الكود لو مملوك لحد تاني
          final allMaps = await db.attendanceDeviceDao.getAllMappings();
          for (final m in allMaps.where((m) => m.deviceId == deviceId && m.externalUserId == newExternalId)) {
            await db.attendanceDeviceDao.deleteMapping(m.id);
          }
          final now = DateTime.now();
          await db.attendanceDeviceDao.addMapping(StaffBiometricMappingsCompanion.insert(
            staffId: staffId, deviceId: deviceId, externalUserId: newExternalId,
            enrollmentStatus: 'enrolled', enrolledAt: Value(now), createdAt: now, updatedAt: now,
          ));
          // حدث الاسم/الوظيفة لو اتغيرت في الإكسل
          var staff = staffById[staffId] ?? await db.staffManagementDao.getStaffById(staffId);
          if (staff != null) {
            bool needUpdate = false;
            String newName = staff.name;
            String newPos = staff.position;
            double newSal = staff.basicSalary;
            if (item.row.name.isNotEmpty && item.row.name.trim() != staff.name) { newName = item.row.name.trim(); needUpdate = true; }
            if (item.row.position.isNotEmpty && item.row.position != staff.position) { newPos = item.row.position; needUpdate = true; }
            if (item.row.basicSalary > 0 && item.row.basicSalary != staff.basicSalary) { newSal = item.row.basicSalary; needUpdate = true; }
            if (needUpdate) {
              await db.staffManagementDao.updateStaff(staff.copyWith(name: newName, position: newPos, basicSalary: newSal, updatedAt: DateTime.now()));
            }
          }
          updated++;
        }
      } catch (e) {
        errors.add('صف ${item.row.excelRowNumber} (${item.row.name}): فشل — $e');
      }
    }
    return StaffExcelCorrectionResult(updated: updated, created: created, skipped: skipped, errors: errors);
  }

  /// كشف الموظفين المكررة الفاضية (بدون حضور وبدون وظيفة حقيقية)
  Future<List<Staff>> findOrphanStaff() async {
    final all = await db.staffManagementDao.getAllStaff();
    final orphans = <Staff>[];
    for (final s in all) {
      final pos = s.position.trim();
      final isGenericPos = pos.isEmpty || pos == 'موظف' || pos == 'عامل';
      final isZeroSalary = s.basicSalary == 0;
      if (!isGenericPos && !isZeroSalary) continue;
      final att = await db.staffManagementDao.getAttendanceByStaff(s.staffId);
      if (att.isEmpty) orphans.add(s);
    }
    return orphans;
  }

  Future<int> deleteOrphanStaff(List<String> staffIds) async {
    int deleted = 0;
    for (final sid in staffIds) {
      final att = await db.staffManagementDao.getAttendanceByStaff(sid);
      if (att.isNotEmpty) continue; // أمان: لا تحذف اللي عنده حضور
      final maps = await db.attendanceDeviceDao.getMappingsForStaff(sid);
      for (final m in maps) { await db.attendanceDeviceDao.deleteMapping(m.id); }
      await db.staffManagementDao.deleteStaff(sid);
      deleted++;
    }
    return deleted;
  }

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
