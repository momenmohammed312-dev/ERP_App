// ignore_for_file: argument_type_not_assignable
import 'dart:math';
import 'package:drift/drift.dart';
import '../core/database/app_database.dart';
import '../core/database/dao/staff_management_dao.dart';
import '../core/models/user_model.dart';
import '../core/services/validation/permission_validator.dart';
import '../services/attendance/attendance_calculation_engine.dart';

class StaffManagementService {
  final StaffManagementDao _dao;
  final AppDatabase? _db;

  StaffManagementService(this._dao, [this._db]);

  // STAFF MANAGEMENT

  Future<String> generateStaffId() async {
    final existingStaff = await _dao.getAllStaff();
    final maxId = existingStaff.fold<int>(0, (max, staff) {
      final numericPart =
          int.tryParse(staff.staffId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return max > numericPart ? max : numericPart;
    });
    return 'STAFF${(maxId + 1).toString().padLeft(4, '0')}';
  }

  Future<void> addNewStaff(
    User? user, {
    required String name,
    required String position,
    required String employmentType,
    required double basicSalary,
    String payFrequency = 'monthly',
    double? weeklySalary,
    String? nationalId,
    String? phone,
    String? email,
    String? address,
    String? department,
    double? hourlyRate,
    DateTime? contractEndDate,
    String? bankName,
    String? bankAccount,
    String? emergencyContact,
    String? emergencyPhone,
    String? notes,
    bool useDefaultSchedule = true,
    String? workScheduleStart,
    String? workScheduleEnd,
    String? workDays,
    String? weekendDay,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.createEmployee,
      'إضافة موظف',
    );
    final staffId = await generateStaffId();

    await _dao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: name,
        position: position,
        employmentType: employmentType,
        basicSalary: basicSalary,
        hireDate: DateTime.now(),
        status: 'active',
        nationalId: Value(nationalId),
        phone: Value(phone),
        email: Value(email),
        address: Value(address),
        department: Value(department),
        hourlyRate: Value(hourlyRate),
        contractEndDate: Value(contractEndDate),
        bankName: Value(bankName),
        bankAccount: Value(bankAccount),
        emergencyContact: Value(emergencyContact),
        emergencyPhone: Value(emergencyPhone),
        notes: Value(notes),
        useDefaultSchedule: Value(useDefaultSchedule),
        workScheduleStart: Value(workScheduleStart),
        workScheduleEnd: Value(workScheduleEnd),
        workDays: Value(workDays),
        weekendDay: Value(weekendDay),
        payFrequency: Value(payFrequency),
        weeklySalary: Value(weeklySalary),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> updateStaffInfo(
    User? user, {
    required String staffId,
    String? name,
    String? position,
    String? department,
    String? employmentType,
    double? basicSalary,
    double? hourlyRate,
    String? phone,
    String? email,
    String? address,
    String? bankName,
    String? bankAccount,
    String? emergencyContact,
    String? emergencyPhone,
    String? notes,
    String? status,
    DateTime? contractEndDate,
    String? payFrequency,
    double? weeklySalary,
    bool? useDefaultSchedule,
    String? workScheduleStart,
    String? workScheduleEnd,
    String? workDays,
    String? weekendDay,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.editEmployee,
      'تعديل موظف',
    );
    final staff = await _dao.getStaffById(staffId);
    if (staff != null) {
      await _dao.updateStaff(
        staff.copyWith(
          name: name ?? staff.name,
          position: position ?? staff.position,
          employmentType: employmentType ?? staff.employmentType,
          basicSalary: basicSalary ?? staff.basicSalary,
          status: status ?? staff.status,
          department: department != null
              ? Value(department)
              : const Value.absent(),
          hourlyRate: hourlyRate != null
              ? Value(hourlyRate)
              : const Value.absent(),
          phone: phone != null ? Value(phone) : const Value.absent(),
          email: email != null ? Value(email) : const Value.absent(),
          address: address != null ? Value(address) : const Value.absent(),
          bankName: bankName != null ? Value(bankName) : const Value.absent(),
          bankAccount: bankAccount != null
              ? Value(bankAccount)
              : const Value.absent(),
          emergencyContact: emergencyContact != null
              ? Value(emergencyContact)
              : const Value.absent(),
          emergencyPhone: emergencyPhone != null
              ? Value(emergencyPhone)
              : const Value.absent(),
          notes: notes != null ? Value(notes) : const Value.absent(),
          contractEndDate: contractEndDate != null
              ? Value(contractEndDate)
              : const Value.absent(),
          payFrequency: payFrequency ?? staff.payFrequency,
          weeklySalary: weeklySalary != null
              ? Value(weeklySalary)
              : const Value.absent(),
          useDefaultSchedule: useDefaultSchedule ?? staff.useDefaultSchedule,
          workScheduleStart: workScheduleStart != null
              ? Value(workScheduleStart)
              : const Value.absent(),
          workScheduleEnd: workScheduleEnd != null
              ? Value(workScheduleEnd)
              : const Value.absent(),
          workDays: workDays != null ? Value(workDays) : const Value.absent(),
          weekendDay: weekendDay != null
              ? Value(weekendDay)
              : const Value.absent(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> terminateStaff(User? user, String staffId) async {
    PermissionValidator.requirePermission(
      user,
      Permission.editEmployee,
      'إنهاء خدمة موظف',
    );
    await updateStaffInfo(user, staffId: staffId, status: 'terminated');
  }

  // ATTENDANCE MANAGEMENT

  Future<void> recordCheckIn(
    String staffId, {
    String? location,
    String source = 'manual',
    int? sourceDeviceId,
    int? rawEventId,
  }) async {
    // Calculate smart status if engine is available
    String status = 'present';
    int? lateMinutes;
    final db = _db;
    if (db != null) {
      try {
        final engine = AttendanceCalculationEngine(
          db,
          db.attendanceDeviceDao,
          _dao,
        );
        final calc = await engine.processCheckIn(staffId);
        status = calc.status;
        lateMinutes = calc.lateMinutes;
      } catch (_) {
        // Fallback to default 'present' if engine fails
      }
    }

    await _dao.checkIn(
      staffId,
      location: location,
      source: source,
      sourceDeviceId: sourceDeviceId,
      rawEventId: rawEventId,
      status: status,
      lateMinutes: lateMinutes,
    );
  }

  /// Returns true if checkout was successful, false if no attendance record exists for today
  Future<bool> recordCheckOut(
    String staffId, {
    String? location,
    String source = 'manual',
    int? sourceDeviceId,
    int? rawEventId,
  }) async {
    // Calculate working hours and overtime if engine is available
    double? workingHours;
    double? overtimeHours;
    String? status;
    int? lateMinutes;
    final db = _db;

    if (db != null) {
      try {
        final engine = AttendanceCalculationEngine(
          db,
          db.attendanceDeviceDao,
          _dao,
        );

        // Get today's attendance to find check-in time
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        final records = await _dao.getAttendanceByStaff(
          staffId,
          startDate: today,
          endDate: tomorrow,
        );
        final todayRecord = records.where((a) {
          final aDate = DateTime(a.date.year, a.date.month, a.date.day);
          return aDate == today;
        }).toList();

        if (todayRecord.isNotEmpty && todayRecord.first.checkInTime != null) {
          final result = await engine.processCheckOut(
            staffId,
            checkInTime: todayRecord.first.checkInTime!,
          );
          workingHours = result.workingHours;
          overtimeHours = result.overtimeHours;
          status = result.status;
          lateMinutes = result.lateMinutes;
        }
      } catch (_) {
        // Fallback: let DAO calculate basic working hours
      }
    }

    return await _dao.checkOut(
      staffId,
      location: location,
      source: source,
      sourceDeviceId: sourceDeviceId,
      rawEventId: rawEventId,
      workingHours: workingHours,
      overtimeHours: overtimeHours,
      status: status,
      lateMinutes: lateMinutes,
    );
  }

  /// Returns true if an attendance record already exists for the given day
  Future<bool> hasAttendanceOnDate(String staffId, DateTime date) async {
    final records = await _dao.getAttendanceOnDate(staffId, date);
    return records.isNotEmpty;
  }

  /// Manual check-in that refuses duplicates: returns true if recorded,
  /// false if a record already exists for today (nothing written).
  /// Used by the manual UI only; the device sync path keeps its own upsert flow.
  Future<bool> recordCheckInTodayOnce(String staffId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (await hasAttendanceOnDate(staffId, today)) return false;
    await recordCheckIn(staffId, source: 'manual');
    return true;
  }

  /// Deletes all attendance records of a staff member for a specific day
  Future<void> deleteAttendanceDay(
    User? user,
    String staffId,
    DateTime date,
  ) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageAttendance,
      'حذف سجل حضور',
    );
    await _dao.deleteAttendanceByDate(staffId, date);
  }

  /// Deletes all imported attendance for a staff (source='import') — لإزالة الدوبلر
  Future<int> deleteImportedForStaff(User? user, String staffId) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageAttendance,
      'حذف حضور مستورد',
    );
    return await _dao.deleteAttendanceByStaffAndSource(staffId, 'import');
  }

  /// يحذف كل حضور لموظف في فترة (أي مصدر) — لفك التعارض مع auto_generated/manual
  Future<int> deleteAttendanceForPeriod(
    User? user,
    String staffId,
    DateTime start,
    DateTime end,
  ) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageAttendance,
      'حذف حضور فترة',
    );
    return await _dao.deleteAttendanceByStaffInRange(staffId, start, end);
  }

  /// حذف نهائي للموظف وكل سجلاته (حضور، سلف، رواتب، إجازات، جزاءات) — لإزالة الاسم من كل السجلات
  Future<void> deleteStaffCompletely(User? user, String staffId) async {
    PermissionValidator.requirePermission(
      user,
      Permission.editEmployee,
      'حذف موظف',
    );
    final db = _dao.attachedDatabase;
    await db.transaction(() async {
      await _dao.deleteStaff(staffId);
      await (db.delete(
        db.attendanceTable,
      )..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(
        db.staffAdvances,
      )..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(
        db.payrollTable,
      )..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(
        db.vacations,
      )..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(
        db.rewardsPenalties,
      )..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(
        db.performanceReviews,
      )..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(
        db.staffDocuments,
      )..where((t) => t.staffId.equals(staffId))).go();
      // بصمة
      try {
        await (db.delete(
          db.staffBiometricMappings,
        )..where((t) => t.staffId.equals(staffId))).go();
      } catch (_) {}
    });
  }

  /// تعديل يدوي (مراقب) مع دعم الوقت الإضافي:
  /// - [overtimeHours] صريح → يُعتمد كما هو (تعديل إداري موثق بسبب [reason]).
  /// - بدون قيمة صريحة ووجود حضور+انصراف → إعادة حساب تلقائي بالمحرك
  ///   (مهلة الإضافي من الإعدادات) لساعات العمل والإضافي معاً.
  /// - بدون أوقات → الاحتفاظ بالقيم المخزنة كما هي.
  Future<void> recordManualOverride(
    User? user,
    String staffId, {
    required DateTime date,
    required String status,
    required String reason,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
    double? permissionHours,
    double? overtimeHours,
  }) async {
    PermissionValidator.requirePermission(user, Permission.manageAttendance);
    if (reason.trim().isEmpty) {
      throw Exception('Reason is required for manual override');
    }

    double? finalOvertime = overtimeHours;
    double? finalWorkingHours;
    if (finalOvertime == null &&
        checkInTime != null &&
        checkOutTime != null &&
        _db != null) {
      try {
        final engine = AttendanceCalculationEngine(
          _db,
          _db.attendanceDeviceDao,
          _dao,
        );
        final calc = await engine.processCheckOut(
          staffId,
          checkInTime: checkInTime,
          checkOutTime: checkOutTime,
        );
        finalOvertime = calc.overtimeHours;
        finalWorkingHours = calc.workingHours;
      } catch (_) {
        // Fallback: تُحفظ الأوقات بدون إعادة حساب
      }
    }

    final entry = AttendanceTableCompanion.insert(
      staffId: staffId,
      date: date,
      status: status,
      checkInTime: Value(checkInTime),
      checkOutTime: Value(checkOutTime),
      workingHours: finalWorkingHours == null
          ? const Value.absent()
          : Value(finalWorkingHours),
      overtimeHours: finalOvertime == null
          ? const Value.absent()
          : Value(finalOvertime),
      notes: Value(notes),
      permissionHours: Value(permissionHours ?? 0),
      source: const Value('admin_override'),
      overrideReason: Value(reason),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final todayRecords = await _dao.getAttendanceOnDate(staffId, date);

    if (todayRecords.isNotEmpty) {
      final current = todayRecords.first;
      final updated = current.copyWith(
        status: status,
        checkInTime: Value(checkInTime),
        checkOutTime: Value(checkOutTime),
        workingHours: Value(finalWorkingHours ?? current.workingHours),
        overtimeHours: finalOvertime ?? current.overtimeHours,
        notes: Value(notes),
        permissionHours: permissionHours ?? current.permissionHours,
        source: const Value('admin_override'),
        overrideReason: Value(reason),
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(updated);
    } else {
      await _dao.addAttendance(entry);
    }
  }

  Future<void> recordManualAttendance(
    String staffId, {
    required DateTime date,
    required String status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    double? workingHours,
    double? overtimeHours,
    String? notes,
    String source = 'manual',
  }) async {
    // خصم ساعة الراحة من ساعات العمل المحسوبة يدوياً (من 8 لـ5 = 8 ساعات)
    var finalWorkingHours = workingHours;
    if (finalWorkingHours != null &&
        checkOutTime != null &&
        checkInTime != null) {
      final breakMinutes = await _getBreakMinutes();
      final breakHrs = breakMinutes / 60.0;
      final raw = checkOutTime.difference(checkInTime).inMinutes / 60.0;
      final computed = raw - breakHrs;
      finalWorkingHours = computed < 0 ? 0 : computed;
    }
    // الإضافي: صريح → يُعتمد، وإلا يُحسب بالمحرك عند وجود الأوقات
    var finalOvertime = overtimeHours;
    if (finalOvertime == null &&
        checkInTime != null &&
        checkOutTime != null &&
        _db != null) {
      try {
        final engine = AttendanceCalculationEngine(
          _db,
          _db.attendanceDeviceDao,
          _dao,
        );
        final calc = await engine.processCheckOut(
          staffId,
          checkInTime: checkInTime,
          checkOutTime: checkOutTime,
        );
        finalOvertime = calc.overtimeHours;
      } catch (_) {
        finalOvertime = 0;
      }
    }
    final entry = AttendanceTableCompanion.insert(
      staffId: staffId,
      date: date,
      status: status,
      checkInTime: Value(checkInTime),
      checkOutTime: Value(checkOutTime),
      workingHours: Value(finalWorkingHours),
      overtimeHours: finalOvertime == null
          ? const Value.absent()
          : Value(finalOvertime),
      notes: Value(notes),
      source: Value(source),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final todayRecords = await _dao.getAttendanceOnDate(staffId, date);

    if (todayRecords.isNotEmpty) {
      final updated = todayRecords.first.copyWith(
        status: status,
        checkInTime: Value(checkInTime),
        checkOutTime: Value(checkOutTime),
        workingHours: Value(finalWorkingHours),
        overtimeHours: finalOvertime ?? todayRecords.first.overtimeHours,
        notes: Value(notes),
        source: Value(source),
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(updated);
    } else {
      await _dao.addAttendance(entry);
    }
  }

  /// إعادة حساب الوقت الإضافي (وساعات العمل) لسجلات فترة — بقاعدة المهلة الحالية.
  /// يتخطى: سجلات `admin_override` (قرار إداري صريح) وأي يوم داخل فترة مرتب `paid`.
  /// العملية كلها في transaction واحدة (atomic). ترجع (أُعيد حسابه، مُتخطى).
  Future<({int recomputed, int skipped})> recomputeOvertimeForPeriod(
    User? user,
    String staffId,
    DateTime start,
    DateTime end,
  ) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageAttendance,
      'إعادة حساب الإضافي',
    );
    final db = _dao.attachedDatabase;
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));

    final rows = await _dao.getAttendanceByStaff(
      staffId,
      startDate: s,
      endDate: e,
    );
    final payrolls = await (db.select(
      db.payrollTable,
    )..where((t) => t.staffId.equals(staffId))).get();
    bool inPaidPeriod(DateTime day) {
      final d = DateTime(day.year, day.month, day.day);
      for (final p in payrolls) {
        if (p.status != 'paid') continue;
        final ps = DateTime(
          p.periodStart.year,
          p.periodStart.month,
          p.periodStart.day,
        );
        final pe = DateTime(
          p.periodEnd.year,
          p.periodEnd.month,
          p.periodEnd.day,
        );
        if (!d.isBefore(ps) && !d.isAfter(pe)) return true;
      }
      return false;
    }

    final engine = AttendanceCalculationEngine(
      db,
      db.attendanceDeviceDao,
      _dao,
    );
    final schedule = await engine.getScheduleForStaff(staffId);
    int recomputed = 0;
    int skipped = 0;
    await db.transaction(() async {
      for (final r in rows) {
        if (r.checkInTime == null) {
          skipped++;
          continue;
        }
        if (r.source == 'admin_override' || inPaidPeriod(r.date)) {
          skipped++;
          continue;
        }
        if (r.checkOutTime != null) {
          final calc = await engine.processCheckOut(
            staffId,
            checkInTime: r.checkInTime!,
            checkOutTime: r.checkOutTime!,
          );
          await _dao.updateAttendance(
            r.copyWith(
              workingHours: Value(calc.workingHours),
              overtimeHours: calc.overtimeHours,
              lateMinutes: calc.lateMinutes,
              status: calc.status,
              updatedAt: DateTime.now(),
            ),
          );
        } else {
          final calc = engine.calculateAttendance(
            checkInTime: r.checkInTime!,
            schedule: schedule,
          );
          await _dao.updateAttendance(
            r.copyWith(
              lateMinutes: calc.lateMinutes,
              status: calc.status,
              updatedAt: DateTime.now(),
            ),
          );
        }
        recomputed++;
      }
    });
    return (recomputed: recomputed, skipped: skipped);
  }

  /// يقرأ عدد دقائق الراحة من الإعدادات (افتراضي 60 دقيقة = ساعة)
  Future<int> _getBreakMinutes() async {
    final db = _db;
    if (db != null) {
      try {
        final settings = await db.select(db.attendanceSettings).get();
        for (final s in settings) {
          if (s.settingKey == 'break_minutes') {
            return int.tryParse(s.settingValue) ?? 60;
          }
        }
      } catch (_) {}
    }
    return 60;
  }

  /// Mark a specific day with a permission (إذن):
  /// - [permissionType] == 'leave': إجازة كاملة (لا يُحسب غياب) — السلوك القديم
  /// - == 'late': إذن حضور متأخر
  /// - == 'early': إذن انصراف مبكر
  /// [excused] = true → لا خصم على التأخير/الانصراف المبكر، false → يُخصم بالساعة
  /// [excusedHours] = عدد ساعات الإذن المسموح بيها (للخصم التناسبي: الفرق فوق المسموح فقط يُخصم)
  Future<void> markLeaveDay(
    String staffId,
    DateTime date, {
    String? notes,
    String source = 'manual',
    String permissionType = 'leave',
    bool excused = false,
    double excusedHours = 0,
  }) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final existing = await _dao.getAttendanceOnDate(staffId, dateOnly);

    final String status;
    if (permissionType == 'late') {
      status = 'late';
    } else if (permissionType == 'early') {
      status = 'early_leave';
    } else {
      status = 'leave';
    }

    if (existing.isNotEmpty) {
      final clearTimes = status == 'leave';
      final rec = existing.first.copyWith(
        status: status,
        excused: excused,
        excusedHours: excusedHours,
        // الإجازة الكاملة بتمسح الأوقات، أما التأخير/الانصراف يحتفظ بالأوقات
        checkInTime: clearTimes
            ? const Value(null)
            : Value(existing.first.checkInTime),
        checkOutTime: clearTimes
            ? const Value(null)
            : Value(existing.first.checkOutTime),
        workingHours: clearTimes
            ? const Value(null)
            : Value(existing.first.workingHours),
        notes: Value(notes),
        source: Value(source),
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(rec);
    } else {
      await _dao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: dateOnly,
          status: status,
          excused: Value(excused),
          excusedHours: Value(excusedHours),
          notes: Value(notes),
          source: Value(source),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  /// إلغاء الإذن ليوم واحد — يرجع excused=false و excusedHours=0
  Future<void> clearExcusedDay(String staffId, DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final existing = await _dao.getAttendanceOnDate(staffId, dateOnly);
    if (existing.isEmpty) return;
    final rec = existing.first.copyWith(
      excused: false,
      excusedHours: 0,
      updatedAt: DateTime.now(),
    );
    await _dao.updateAttendance(rec);
  }

  /// عكس حضور فقط — يصلح الاستيراد المعكوس (الحضور راح في الانصراف) بدون ما يلمس الانصراف الأصلي
  Future<int> swapAttendanceTimesForPeriod(
    String staffId,
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    int count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final list = await _dao.getAttendanceOnDate(staffId, d);
      if (list.isEmpty) continue;
      final r = list.first;
      if (r.checkOutTime == null) continue;
      // انقل قيمة الانصراف (اللي هي حضور بالغلط) للحضور، وسيب الانصراف الأصلي زي ما هو (يجي من البصمة عادي)
      final shouldFix =
          r.checkInTime == null ||
          (r.checkInTime != null &&
              r.checkOutTime != null &&
              r.checkInTime!.isAfter(r.checkOutTime!));
      if (!shouldFix) continue;
      final swapped = r.copyWith(
        checkInTime: Value(r.checkOutTime),
        // ميعدلش الانصراف — سيبه زي ما هو
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(swapped);
      count++;
    }
    return count;
  }

  /// إلغاء الإذن لفترة — يرجع كل الأيام في الفترة إلى بدون إذن
  Future<int> clearExcusedPeriod(
    String staffId,
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    int count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final existing = await _dao.getAttendanceOnDate(staffId, d);
      if (existing.isEmpty) continue;
      if (!existing.first.excused && existing.first.excusedHours == 0) continue;
      final rec = existing.first.copyWith(
        excused: false,
        excusedHours: 0,
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(rec);
      count++;
    }
    return count;
  }

  Future<AttendanceSummary> getAttendanceSummary(
    String staffId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final attendanceRecords = await _dao.getAttendanceByStaff(
      staffId,
      startDate: startDate,
      endDate: endDate,
    );

    int presentDays = 0;
    int absentDays = 0;
    int leaveDays = 0;
    int lateDays = 0;
    double totalHours = 0.0;
    double totalOvertime = 0.0;
    int totalLateMinutes = 0;
    int totalEarlyMinutes = 0;
    int totalLateExcusedMinutes = 0;
    int totalEarlyExcusedMinutes = 0;
    double totalLateHours = 0.0;
    double totalPermissionHours = 0.0;
    // B1: مخزن-فقط للصفوف بلا وقت بصمة (استيراد تاريخي لا يمكن إعادة حسابه)
    double storedOnlyLateHours = 0.0;

    ScheduleConfig? schedule;
    final db = _db;
    if (db != null) {
      try {
        final engine = AttendanceCalculationEngine(
          db,
          db.attendanceDeviceDao,
          _dao,
        );
        schedule = await engine.getScheduleForStaff(staffId);
      } catch (_) {}
    }

    bool isLateByTime(Attendance r) {
      if (r.checkInTime == null || schedule == null) return false;
      if (r.excused && r.excusedHours <= 0) return false;
      final ciMin = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
      final graceEnd =
          schedule.workStartMinutesSinceMidnight + schedule.gracePeriodMinutes;
      return ciMin > graceEnd;
    }

    for (final record in attendanceRecords) {
      final effectiveIsLate =
          (record.status == 'late' ||
          (record.status == 'present' && isLateByTime(record)));
      switch (record.status) {
        case 'present':
          if (effectiveIsLate) {
            lateDays++;
            presentDays++;
            final ciMin =
                record.checkInTime!.hour * 60 + record.checkInTime!.minute;
            final graceEnd =
                schedule!.workStartMinutesSinceMidnight +
                schedule.gracePeriodMinutes;
            if (ciMin > graceEnd) {
              // القاعدة المتفق عليها: التأخير من بداية الدوام شاملاً السماح
              final actual = ciMin - schedule.workStartMinutesSinceMidnight;
              totalLateMinutes += actual;
              if (record.excused && record.excusedHours > 0) {
                totalLateExcusedMinutes += (record.excusedHours * 60).round();
              }
            }
          } else {
            presentDays++;
          }
          break;
        case 'absent':
          absentDays++;
          break;
        case 'leave':
          leaveDays++;
          break;
        case 'late':
          presentDays++;
          if (record.checkInTime != null && schedule != null) {
            if (record.excused && record.excusedHours <= 0) {
            } else {
              lateDays++;
              final ciMin =
                  record.checkInTime!.hour * 60 + record.checkInTime!.minute;
              final graceEnd =
                  schedule.workStartMinutesSinceMidnight +
                  schedule.gracePeriodMinutes;
              if (ciMin > graceEnd) {
                // القاعدة المتفق عليها: التأخير من بداية الدوام شاملاً السماح
                final actual = ciMin - schedule.workStartMinutesSinceMidnight;
                totalLateMinutes += actual;
              }
              if (record.excused && record.excusedHours > 0) {
                totalLateExcusedMinutes += (record.excusedHours * 60).round();
              }
            }
          } else if (record.excused && record.excusedHours > 0) {
            totalLateExcusedMinutes += (record.excusedHours * 60).round();
          }
          break;
        case 'early_leave':
          if (record.checkInTime != null &&
              record.checkOutTime != null &&
              schedule != null) {
            final coMin =
                record.checkOutTime!.hour * 60 + record.checkOutTime!.minute;
            final endMin = schedule.workEndMinutesSinceMidnight;
            if (coMin < endMin) lateDays++;
          }
          presentDays++;
          if (record.excused && record.excusedHours > 0) {
            totalEarlyExcusedMinutes += (record.excusedHours * 60).round();
          }
          break;
      }

      if (record.checkOutTime != null && schedule != null) {
        final coMin =
            record.checkOutTime!.hour * 60 + record.checkOutTime!.minute;
        final endMin = schedule.workEndMinutesSinceMidnight;
        if (coMin < endMin) {
          final actual = endMin - coMin;
          if (record.excused && record.excusedHours <= 0) {
          } else {
            if (record.status != 'early_leave' &&
                record.excused &&
                record.excusedHours > 0) {
              totalEarlyExcusedMinutes += (record.excusedHours * 60).round();
            }
            totalEarlyMinutes += actual;
          }
        }
      }

      totalHours += record.workingHours ?? 0.0;
      totalOvertime += record.overtimeHours;
      // B1 per-record: المخزن يُعتمد فقط لصف بلا checkInTime (لا يمكن
      // إعادة حسابه حياً) — الصفوف الموقوتة مصدرها الحلقة أعلاه دائماً،
      // فلا إسقاط متبادل بين المخزن والحي على مستوى الفترة.
      if (record.checkInTime == null && record.lateMinutes > 0) {
        storedOnlyLateHours += record.lateMinutes / 60.0;
      }
      if (record.permissionHours > 0) {
        totalPermissionHours += record.permissionHours;
      }
    }

    // الحي (من الصفوف الموقوتة) + المخزن-لغير-الموقوت فقط.
    totalLateHours = totalLateMinutes / 60.0 + storedOnlyLateHours;

    if (totalPermissionHours == 0 &&
        (totalLateExcusedMinutes + totalEarlyExcusedMinutes) > 0) {
      totalPermissionHours =
          (totalLateExcusedMinutes + totalEarlyExcusedMinutes) / 60.0;
    }

    return AttendanceSummary(
      totalDays: attendanceRecords.length,
      presentDays: presentDays,
      absentDays: absentDays,
      leaveDays: leaveDays,
      lateDays: lateDays,
      totalHours: totalHours,
      totalOvertime: totalOvertime,
      totalLateMinutes: totalLateMinutes,
      totalEarlyMinutes: totalEarlyMinutes,
      totalLateExcusedMinutes: totalLateExcusedMinutes,
      totalEarlyExcusedMinutes: totalEarlyExcusedMinutes,
      totalLateHours: totalLateHours,
      totalPermissionHours: totalPermissionHours,
    );
  }

  // VACATION MANAGEMENT

  Future<void> requestVacation({
    required String staffId,
    required String vacationType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? contactDuringVacation,
    String? handoverTo,
  }) async {
    final totalDays = endDate.difference(startDate).inDays + 1;

    await _dao.addVacation(
      VacationsCompanion.insert(
        staffId: staffId,
        vacationType: vacationType,
        startDate: startDate,
        endDate: endDate,
        totalDays: totalDays,
        reason: Value(reason),
        status: 'pending',
        contactDuringVacation: Value(contactDuringVacation ?? ''),
        handoverTo: Value(handoverTo ?? ''),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<int> getAvailableVacationDays(
    String staffId,
    String vacationType,
  ) async {
    // This is a simplified calculation - in a real system, you'd have more complex rules
    final staff = await _dao.getStaffById(staffId);
    if (staff == null) return 0;

    final hireDate = staff.hireDate;
    final now = DateTime.now();
    final yearsOfService = now.difference(hireDate).inDays / 365;

    // Basic vacation days calculation
    int baseDays = 21; // Standard 21 days per year
    if (vacationType == 'annual') {
      baseDays = (baseDays * yearsOfService).floor();
    } else if (vacationType == 'sick') {
      baseDays = 14; // 14 sick days per year
    }

    // Subtract used vacation days
    final usedVacations = await _dao.getVacationsByStaff(staffId);
    final usedDays = usedVacations
        .where((v) => v.vacationType == vacationType && v.status == 'approved')
        .fold<int>(0, (sum, v) => sum + v.totalDays);

    return max(0, baseDays - usedDays);
  }

  // ADVANCE MANAGEMENT

  Future<void> requestAdvance(
    User? user, {
    required String staffId,
    required double amount,
    required String reason,
    int? installmentMonths,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'طلب سلفة',
    );
    await _dao.addAdvance(
      StaffAdvancesCompanion.insert(
        staffId: staffId,
        amount: amount,
        reason: Value(reason),
        requestDate: DateTime.now(),
        status: 'pending',
        installmentMonths: Value(installmentMonths),
        monthlyDeduction: installmentMonths != null
            ? Value(amount / installmentMonths)
            : const Value.absent(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> approveAdvance(User? user, int advanceId) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'اعتماد سلفة',
    );
    await _dao.approveAdvance(advanceId, user?.fullName ?? 'admin');
  }

  Future<void> rejectAdvance(User? user, int advanceId, String reason) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'رفض سلفة',
    );
    await _dao.rejectAdvance(advanceId, user?.fullName ?? 'admin', reason);
  }

  // PAYROLL MANAGEMENT

  Future<void> calculatePayroll(
    User? user,
    String staffId,
    String payrollPeriod, {
    double commitmentBonus = 0,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'حساب الرواتب',
    );
    final staff = await _dao.getStaffById(staffId);
    if (staff == null) return;

    await calculatePeriodPay(
      staffId: staffId,
      payrollPeriod: payrollPeriod,
      periodStart: _getPeriodStart(payrollPeriod),
      periodEnd: _getPeriodEnd(payrollPeriod),
      baseSalary: staff.basicSalary,
      dailyDivisor: 30,
      commitmentBonus: commitmentBonus,
    );
  }

  /// Shared payroll pipeline for any period (monthly or weekly).
  /// Identical behavior to the old monthly path when called with the monthly
  /// base salary and dailyDivisor 30 — STEP 2 extraction, no logic change.
  Future<void> calculatePeriodPay({
    required String staffId,
    required String payrollPeriod,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double baseSalary,
    required double dailyDivisor,
    double commitmentBonus = 0,
    bool applyCommitmentBonus = true,
    bool capAdvancesToNet = false,
  }) async {
    final staff = await _dao.getStaffById(staffId);
    if (staff == null) return;
    final basicSalary = baseSalary;

    // توليد الغياب تلقائياً لكل يوم في الفترة قبل الحساب — يحترم الجمعة/الإجازة
    // مهم: لا نولّد غياب لأيام مستقبلية (بعد اليوم) — وإلا يظهر غياب 30 يوم مقدماً كما في الصورة
    final dbForAbsence = _dao.attachedDatabase;
    try {
      // تنظيف غياب مستقبلي قديم اتولد بالغلط قبل الإصلاح
      try {
        await _dao.deleteFutureAutoAbsences();
      } catch (_) {}
      final engine = AttendanceCalculationEngine(
        dbForAbsence,
        dbForAbsence.attendanceDeviceDao,
        _dao,
      );
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final effectiveEnd = periodEnd.isAfter(today) ? today : periodEnd;
      for (
        var d = DateTime(periodStart.year, periodStart.month, periodStart.day);
        !d.isAfter(
          DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day),
        );
        d = d.add(const Duration(days: 1))
      ) {
        await engine.generateAbsencesForDate(d);
      }
    } catch (_) {}
    // Get attendance data — لو فيه ملخص شهري مستورد (من الورق) استخدمه مباشرة (تأخير/إضافي/إذن/غياب منفصل)
    var attendanceSummary = await getAttendanceSummary(
      staffId,
      periodStart,
      periodEnd,
    );
    // override من monthly_attendance_summary_table لو موجود لنفس الفترة
    try {
      final summaryRow =
          await (dbForAbsence.select(
                dbForAbsence.monthlyAttendanceSummaryTable,
              )..where(
                (t) =>
                    t.staffId.equals(staffId) & t.period.equals(payrollPeriod),
              ))
              .getSingleOrNull();
      if (summaryRow != null) {
        attendanceSummary = AttendanceSummary(
          totalDays: attendanceSummary.totalDays,
          presentDays: attendanceSummary.presentDays,
          absentDays: summaryRow.absentDays,
          leaveDays: attendanceSummary.leaveDays,
          lateDays: summaryRow.lateHours > 0 ? 1 : 0,
          totalHours: attendanceSummary.totalHours,
          totalOvertime: summaryRow.overtimeHours,
          totalLateMinutes: (summaryRow.lateHours * 60).round(),
          // B2: totalLateHours هي المستهلكة فعلياً في معادلة الخصم —
          // إسقاطها كان يُصفّر خصم التأخير لكل الفترات المستوردة.
          totalLateHours: summaryRow.lateHours,
          totalEarlyMinutes: 0,
          totalLateExcusedMinutes: (summaryRow.excusedHours * 60).round(),
          totalEarlyExcusedMinutes: 0,
        );
      }
    } catch (_) {}

    // Payroll lifecycle guard first: paid rows are immutable.
    final db = _dao.attachedDatabase;
    final existingPayroll =
        await (db.select(db.payrollTable)..where(
              (t) =>
                  t.staffId.equals(staffId) &
                  t.payrollPeriod.equals(payrollPeriod),
            ))
            .getSingleOrNull();
    if (existingPayroll != null && existingPayroll.status == 'paid') {
      throw Exception('تم صرف راتب هذه الفترة بالفعل ولا يمكن إعادة احتسابه');
    }

    // Advance shares (remaining-aware): an advance contributes at most its
    // unpaid remainder; fully-covered advances are settled opportunistically.
    // Recalc neutrality: the deleted row's advance impact is reversed first
    // (pro-rata by paidAmount) so repeated recalcs don't inflate paidAmount.
    final advances = await _dao.getAdvancesByStaff(staffId);
    // فترة الاستحقاق: null = سلوك قديم (كل مرتب)؛ وإلا تبدأ من الفترة
    // المعينة وتستمر (المقارنة النصية صالحة لصيغ YYYY-MM[-Wn] المصفّرة).
    final eligibleAdvances = advances
        .where(
          (a) =>
              (a.status == 'approved' || a.status == 'paid') &&
              (a.deductOnPeriod == null ||
                  payrollPeriod.compareTo(a.deductOnPeriod!) >= 0),
        )
        .toList();

    final adjustedPaid = <int, double>{
      for (final a in eligibleAdvances) a.id: a.paidAmount,
    };
    var toReverse = existingPayroll?.advances ?? 0.0;
    if (toReverse > 0) {
      final totalPaid = adjustedPaid.values.fold(0.0, (s, v) => s + v);
      for (final a in eligibleAdvances) {
        if (totalPaid <= 0 || toReverse <= 0) break;
        final have = adjustedPaid[a.id]!;
        final refund = toReverse * (have / totalPaid);
        final applied = refund < have ? refund : have;
        adjustedPaid[a.id] = have - applied;
        toReverse -= applied;
      }
    }

    final advanceShares = <int, double>{};
    final settledIds = <int>[];
    for (final a in eligibleAdvances) {
      final installment =
          (a.installmentMonths != null &&
              a.installmentMonths! > 1 &&
              a.monthlyDeduction != null &&
              a.monthlyDeduction! > 0)
          ? a.monthlyDeduction!
          : a.amount;
      final remaining = a.amount - (adjustedPaid[a.id] ?? 0);
      if (remaining <= 0) {
        settledIds.add(a.id);
        continue;
      }
      advanceShares[a.id] = installment < remaining ? installment : remaining;
    }
    double totalAdvances = advanceShares.values.fold(0.0, (s, v) => s + v);

    // Get rewards and penalties for the period
    // (the old non-paid row, if any, is deleted inside the final txn below)

    final allRewardsPenalties =
        await (db.select(db.rewardsPenalties)..where(
              (t) => t.staffId.equals(staffId) & t.status.equals('active'),
            ))
            .get();
    final periodRewards = allRewardsPenalties
        .where(
          (rp) =>
              rp.effectiveDate.isAfter(
                periodStart.subtract(const Duration(days: 1)),
              ) &&
              rp.effectiveDate.isBefore(periodEnd.add(const Duration(days: 1))),
        )
        .toList();

    double rewardsTotal = 0.0;
    double penaltiesTotal = 0.0;
    double allowancesTotal = 0.0;
    for (final rp in periodRewards) {
      final amount = rp.amount ?? 0.0;
      if (rp.category == 'allowance') {
        allowancesTotal += amount;
      } else if (rp.type == 'reward') {
        rewardsTotal += amount;
      } else if (rp.type == 'penalty') {
        penaltiesTotal += amount;
      }
    }

    int workingDaysInPeriod = 0;
    try {
      final engTmp = AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        _dao,
      );
      for (
        var d = DateTime(periodStart.year, periodStart.month, periodStart.day);
        !d.isAfter(DateTime(periodEnd.year, periodEnd.month, periodEnd.day));
        d = d.add(const Duration(days: 1))
      ) {
        final sched = await engTmp.getScheduleForStaff(staffId);
        if (engTmp.isWorkDay(d, sched)) workingDaysInPeriod++;
      }
    } catch (_) {}
    if (workingDaysInPeriod == 0) workingDaysInPeriod = 30;

    final engine = AttendanceCalculationEngine(
      db,
      db.attendanceDeviceDao,
      _dao,
    );
    final scheduleConfig = await engine.getScheduleForStaff(staffId);
    final standardHoursPerDay = scheduleConfig.standardHoursPerDay;
    final overtimeMultiplier = scheduleConfig.overtimeRateMultiplier;

    final hourlyRate =
        staff.hourlyRate ?? (basicSalary / dailyDivisor / standardHoursPerDay);

    // مكافأة الحضور الكامل (بصمة كاملة) — تُمنح لو لم يغب الموظف أي يوم ولم يأخذ إجازة
    // مكافأة التزام (تُمرر من شاشة احتساب المرتب، افتراضي 200)
    double commitmentBonusVal = commitmentBonus;
    if (applyCommitmentBonus && commitmentBonusVal == 0) {
      try {
        final pabRow =
            await (db.select(db.attendanceSettings)..where(
                  (t) => t.settingKey.equals('perfect_attendance_bonus'),
                ))
                .getSingleOrNull();
        final def = double.tryParse(pabRow?.settingValue ?? '0') ?? 0;
        if (def > 0 &&
            attendanceSummary.absentDays == 0 &&
            attendanceSummary.leaveDays == 0 &&
            attendanceSummary.totalLateHours == 0) {
          commitmentBonusVal = def;
        }
      } catch (_) {}
    }

    final overtimePay =
        attendanceSummary.totalOvertime * hourlyRate * overtimeMultiplier;
    final lateDeduction = attendanceSummary.totalLateHours * hourlyRate * 1.5;
    final permissionDeduction =
        attendanceSummary.totalPermissionHours * hourlyRate * 1.0;
    // غياب: يوم = الأساسي÷dailyDivisor (مع المضاعف من الإعدادات)
    double absenceMult = 1.0;
    try {
      final amRow =
          await (db.select(db.attendanceSettings)..where(
                (t) => t.settingKey.equals('absence_penalty_days_multiplier'),
              ))
              .getSingleOrNull();
      absenceMult = double.tryParse(amRow?.settingValue ?? '1') ?? 1.0;
    } catch (_) {}
    final absenceDeduction =
        attendanceSummary.absentDays *
        (basicSalary / dailyDivisor) *
        absenceMult;

    // سقف السلفة (للأسبوعي فقط): الخصم لا يتجاوز الصافي المتاح قبل السلفة،
    // والصافي لا ينزل تحت الصفر بسبب سلفة — والباقي يُرحّل تلقائياً لأن
    // رصيد السلفة لا ينقص إلا بما خُصم فعلاً (يُخصم مجدداً في الفترة التالية).
    // عند التوزيع على سقف أقل، تُوزع الحصص بترتيب الـid (حتمي).
    double totalAdvancesCapped = totalAdvances;
    var appliedShares = Map<int, double>.from(advanceShares);
    if (capAdvancesToNet && totalAdvances > 0) {
      final netBeforeAdvances =
          basicSalary +
          overtimePay +
          allowancesTotal +
          rewardsTotal +
          commitmentBonusVal -
          (penaltiesTotal +
              lateDeduction +
              permissionDeduction +
              absenceDeduction);
      final cap = netBeforeAdvances < 0 ? 0.0 : netBeforeAdvances;
      if (totalAdvancesCapped > cap) {
        var leftover = cap;
        totalAdvancesCapped = 0.0;
        appliedShares = {};
        final ids = advanceShares.keys.toList()..sort();
        for (final id in ids) {
          if (leftover <= 0) break;
          final take = advanceShares[id]! < leftover
              ? advanceShares[id]!
              : leftover;
          appliedShares[id] = take;
          totalAdvancesCapped += take;
          leftover -= take;
        }
      }
    }

    final deductions =
        totalAdvancesCapped +
        penaltiesTotal +
        lateDeduction +
        permissionDeduction +
        absenceDeduction;

    final netSalary =
        basicSalary +
        overtimePay +
        allowancesTotal +
        rewardsTotal +
        commitmentBonusVal -
        deductions;

    // Final writes are atomic: advance progress + old-row delete + new row.
    // A crash can never leave paidAmount advanced without its payroll row
    // (or a deleted row without its replacement).
    await db.transaction(() async {
      for (final entry in appliedShares.entries) {
        final adv = eligibleAdvances.firstWhere((a) => a.id == entry.key);
        final newPaid = (adjustedPaid[entry.key] ?? 0) + entry.value;
        await _dao.applyAdvanceDeduction(
          advanceId: entry.key,
          newPaidAmount: newPaid,
          settled: newPaid >= adv.amount,
        );
      }
      for (final id in settledIds) {
        final adv = eligibleAdvances.firstWhere((a) => a.id == id);
        await _dao.applyAdvanceDeduction(
          advanceId: id,
          newPaidAmount: adv.paidAmount,
          settled: true,
        );
      }
      if (existingPayroll != null) {
        await (db.delete(
          db.payrollTable,
        )..where((t) => t.id.equals(existingPayroll.id))).go();
      }
      await db
          .into(db.payrollTable)
          .insert(
            PayrollTableCompanion.insert(
              staffId: staffId,
              payrollPeriod: payrollPeriod,
              periodStart: periodStart,
              periodEnd: periodEnd,
              basicSalary: basicSalary,
              overtimeHours: Value(attendanceSummary.totalOvertime),
              overtimeRate: Value(hourlyRate * overtimeMultiplier),
              overtimePay: Value(overtimePay),
              allowances: Value(allowancesTotal),
              deductions: Value(deductions),
              advances: Value(totalAdvancesCapped),
              lateHours: Value(attendanceSummary.totalLateHours),
              lateDeduction: Value(lateDeduction),
              permissionHours: Value(attendanceSummary.totalPermissionHours),
              permissionDeduction: Value(permissionDeduction),
              netSalary: netSalary,
              workingDays: Value(workingDaysInPeriod),
              presentDays: Value(attendanceSummary.presentDays),
              absentDays: Value(attendanceSummary.absentDays),
              leaveDays: Value(attendanceSummary.leaveDays),
              rewardsTotal: Value(rewardsTotal),
              bonus: Value(commitmentBonusVal),
              penaltiesTotal: Value(penaltiesTotal),
              status: 'calculated',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    });
  }

  Future<void> payAdvance(
    User? user,
    int advanceId,
    String paymentMethod,
  ) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'صرف سلفة',
    );
    final db = _dao.attachedDatabase;
    final isDayOpen = await db.dayDao.isDayOpen();
    if (!isDayOpen) {
      throw Exception('يجب فتح يوم مالي أولاً');
    }
    return db.transaction(() async {
      final advance = await (db.select(
        db.staffAdvances,
      )..where((t) => t.id.equals(advanceId))).getSingleOrNull();
      if (advance == null || advance.status == 'paid') return;

      await (db.update(
        db.staffAdvances,
      )..where((t) => t.id.equals(advanceId))).write(
        StaffAdvancesCompanion(
          status: const Value('paid'),
          paymentDate: Value(DateTime.now()),
          paymentMethod: Value(paymentMethod),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final desc = 'سلفة موظف: ${advance.staffId}';
      final now = DateTime.now();
      await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          id: '${now.millisecondsSinceEpoch}_advance',
          description: desc,
          amount: advance.amount,
          date: Value(now),
          category: 'other_expenses',
          paymentMethod: Value(paymentMethod),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${now.millisecondsSinceEpoch}_advance',
          entityType: 'StaffAdvance',
          refId: advance.staffId,
          date: DateTime.now(),
          description: desc,
          debit: const Value(0.0),
          credit: Value(advance.amount),
          origin: 'expense',
          paymentMethod: Value(paymentMethod),
        ),
      );
    });
  }

  Future<void> payPayroll(
    User? user,
    int payrollId,
    String paymentMethod,
  ) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'صرف رواتب',
    );
    final db = _dao.attachedDatabase;
    final isDayOpen = await db.dayDao.isDayOpen();
    if (!isDayOpen) {
      throw Exception('يجب فتح يوم مالي أولاً');
    }
    return db.transaction(() async {
      final payroll = await (db.select(
        db.payrollTable,
      )..where((t) => t.id.equals(payrollId))).getSingleOrNull();
      if (payroll == null || payroll.status == 'paid') return;

      await (db.update(
        db.payrollTable,
      )..where((t) => t.id.equals(payrollId))).write(
        PayrollTableCompanion(
          status: const Value('paid'),
          paymentDate: Value(DateTime.now()),
          paymentMethod: Value(paymentMethod),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final desc =
          'راتب موظف: ${payroll.staffId} للفترة ${payroll.payrollPeriod}';
      final now = DateTime.now();
      final expenseId = '${now.millisecondsSinceEpoch}_payroll';
      await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          id: expenseId,
          description: desc,
          amount: payroll.netSalary,
          date: Value(now),
          category: 'salaries',
          paymentMethod: Value(paymentMethod),
        ),
      );

      await (db.update(db.payrollTable)..where((t) => t.id.equals(payrollId)))
          .write(PayrollTableCompanion(expenseRefId: Value(expenseId)));

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_payroll',
          entityType: 'Payroll',
          refId: payroll.staffId,
          date: DateTime.now(),
          description: desc,
          debit: const Value(0.0),
          credit: Value(payroll.netSalary),
          origin: 'expense',
          paymentMethod: Value(paymentMethod),
        ),
      );
    });
  }

  /// نطاق المستحق للصرف: مرتبات غير مدفوعة لموظفين نشطين فقط.
  /// المدفوع مسبقاً والمنتهية خدمتهم (أو المحذوفون) مستبعدون مع بيان عددهم ومبلغهم.
  Future<DisbursementBreakdown> getDisbursementBreakdown(
    String payrollPeriod, {
    Set<int>? onlyIds,
  }) async {
    final db = _dao.attachedDatabase;
    var rows = await (db.select(
      db.payrollTable,
    )..where((t) => t.payrollPeriod.equals(payrollPeriod))).get();
    // تحديد اختياري من الشيك بوكس: فارغ/null = الكل
    if (onlyIds != null && onlyIds.isNotEmpty) {
      rows = rows.where((p) => onlyIds.contains(p.id)).toList();
    }
    final staffList = await _dao.getAllStaff();
    final activeIds = {
      for (final s in staffList)
        if (s.isActive && s.status == 'active') s.staffId,
    };
    final payable = <Payroll>[];
    int paidCount = 0;
    double paidTotal = 0;
    int excludedCount = 0;
    double excludedTotal = 0;
    for (final p in rows) {
      if (p.status == 'paid') {
        paidCount++;
        paidTotal += p.netSalary;
      } else if (activeIds.contains(p.staffId)) {
        payable.add(p);
      } else {
        excludedCount++;
        excludedTotal += p.netSalary;
      }
    }
    return DisbursementBreakdown(
      payable: payable,
      paidCount: paidCount,
      paidTotal: paidTotal,
      excludedCount: excludedCount,
      excludedTotal: excludedTotal,
      voucherNo: await _nextVoucherNo(db, payrollPeriod),
    );
  }

  /// رقم مستند متسلسل للفترة: `PAY-period-n` حيث n = مستندات الفترة السابقة + 1.
  /// مشتق من وصف قيود المصروفات المجمعة — لا جدول جديد.
  /// ملاحظة: ExpenseDao.insertExpense يستبدل الـid بـUUID، لذا الترتيب
  /// يعتمد على الوصف ('صرف مرتبات الفترة period') لا على الـid.
  Future<String> _nextVoucherNo(AppDatabase db, String payrollPeriod) async {
    try {
      final all = await db.select(db.expenses).get();
      final marker = 'صرف مرتبات الفترة $payrollPeriod';
      final n =
          all
              .where(
                (e) =>
                    e.category == 'salaries' && e.description.contains(marker),
              )
              .length +
          1;
      return 'PAY-$payrollPeriod-$n';
    } catch (_) {
      return 'PAY-$payrollPeriod-1';
    }
  }

  /// اعتماد جماعي لمرتبات `calculated` المستحقة (نشطين فقط) في فترة.
  /// ترجع عدد المرتبات المعتمدة. المدفوع والمنتهون لا يُمسون.
  Future<int> approvePayrollsForPeriod(
    User? user,
    String payrollPeriod, {
    Set<int>? onlyIds,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'اعتماد رواتب',
    );
    final db = _dao.attachedDatabase;
    final breakdown = await getDisbursementBreakdown(
      payrollPeriod,
      onlyIds: onlyIds,
    );
    final targets = breakdown.payable
        .where((p) => p.status == 'calculated')
        .toList();
    if (targets.isEmpty) return 0;
    final now = DateTime.now();
    await db.transaction(() async {
      for (final p in targets) {
        await (db.update(
          db.payrollTable,
        )..where((t) => t.id.equals(p.id))).write(
          PayrollTableCompanion(
            status: const Value('approved'),
            approvedBy: Value(user?.fullName),
            approvedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
    return targets.length;
  }

  /// صرف المستحق لفترة في transaction واحدة:
  /// يعتمد المحسوب المتبقي (نشطين فقط) تلقائياً، ثم يصرف الكل المعتمد
  /// بقيد مصرف واحد + قيد أستاذ واحد بالإجمالي، وربط كل مرتب برقم القيد.
  /// المدفوع والمنتهون مستبعدون. يشترط يوماً مالياً مفتوحاً.
  /// ترجع (عدد المصروف، الإجمالي، رقم المستند).
  Future<({int count, double total, String voucherNo})> payPayrollsForPeriod(
    User? user,
    String payrollPeriod,
    String paymentMethod, {
    Set<int>? onlyIds,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'صرف رواتب',
    );
    final db = _dao.attachedDatabase;
    final isDayOpen = await db.dayDao.isDayOpen();
    if (!isDayOpen) {
      throw Exception('يجب فتح يوم مالي أولاً');
    }
    return db.transaction(() async {
      final now = DateTime.now();
      final staffList = await _dao.getAllStaff();
      final activeIds = {
        for (final s in staffList)
          if (s.isActive && s.status == 'active') s.staffId,
      };
      var rows = await (db.select(
        db.payrollTable,
      )..where((t) => t.payrollPeriod.equals(payrollPeriod))).get();
      // تحديد اختياري من الشيك بوكس: فارغ/null = الكل
      if (onlyIds != null && onlyIds.isNotEmpty) {
        rows = rows.where((p) => onlyIds.contains(p.id)).toList();
      }
      // اعتماد تلقائي للمحسوب المتبقي (نشطين فقط) داخل نفس الـtransaction
      final toApprove = rows
          .where(
            (p) => p.status == 'calculated' && activeIds.contains(p.staffId),
          )
          .toList();
      for (final p in toApprove) {
        await (db.update(
          db.payrollTable,
        )..where((t) => t.id.equals(p.id))).write(
          PayrollTableCompanion(
            status: const Value('approved'),
            approvedBy: Value(user?.fullName),
            approvedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
      rows = await (db.select(
        db.payrollTable,
      )..where((t) => t.payrollPeriod.equals(payrollPeriod))).get();
      final toPay = rows
          .where((p) => p.status == 'approved' && activeIds.contains(p.staffId))
          .toList();
      final voucherNo = await _nextVoucherNo(db, payrollPeriod);
      if (toPay.isEmpty) return (count: 0, total: 0.0, voucherNo: voucherNo);

      final total = toPay.fold(0.0, (s, p) => s + p.netSalary);
      final batchId = '${now.millisecondsSinceEpoch}_${payrollPeriod}_batch';
      final desc =
          'مستند $voucherNo: صرف مرتبات الفترة $payrollPeriod (${toPay.length} موظف)';

      // insertExpense يستبدل الـid بـUUID — نلتقط الصف الفعلي للربط الصحيح
      final expense = await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          id: batchId,
          description: desc,
          amount: total,
          date: Value(now),
          category: 'salaries',
          paymentMethod: Value(paymentMethod),
        ),
      );

      for (final p in toPay) {
        await (db.update(
          db.payrollTable,
        )..where((t) => t.id.equals(p.id))).write(
          PayrollTableCompanion(
            status: const Value('paid'),
            paymentDate: Value(now),
            paymentMethod: Value(paymentMethod),
            expenseRefId: Value(expense.id),
            updatedAt: Value(now),
          ),
        );
      }

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: batchId,
          entityType: 'Payroll',
          refId: payrollPeriod,
          date: now,
          description: desc,
          debit: const Value(0.0),
          credit: Value(total),
          origin: 'expense',
          paymentMethod: Value(paymentMethod),
        ),
      );
      return (count: toPay.length, total: total, voucherNo: voucherNo);
    });
  }

  /// Weekly bounds (locked rules): week runs Saturday → Thursday (6 days),
  /// payday is Thursday. The week belongs to its Thursday's month, and Wn is
  /// that Thursday's order within its month (1..5).
  /// Example: Thu 2026-09-03 → W1 = Sat 2026-08-29 .. Thu 2026-09-03.
  (DateTime, DateTime) weekBounds(int year, int month, int week) {
    if (week < 1) throw Exception('رقم الأسبوع غير صالح: $week');
    var thursday = DateTime(year, month, 1);
    while (thursday.weekday != DateTime.thursday) {
      thursday = thursday.add(const Duration(days: 1));
    }
    thursday = thursday.add(Duration(days: (week - 1) * 7));
    if (thursday.month != month || thursday.year != year) {
      throw Exception(
        'لا يوجد أسبوع رقم $week في $year-${month.toString().padLeft(2, '0')}',
      );
    }
    final day = DateTime(thursday.year, thursday.month, thursday.day);
    final start = day.subtract(const Duration(days: 5)); // Saturday
    final end = DateTime(
      thursday.year,
      thursday.month,
      thursday.day,
      23,
      59,
      59,
    );
    return (start, end);
  }

  /// Weekly payroll (locked rules): eligibility = payFrequency 'weekly' +
  /// independent weeklySalary; daily = weekly ÷ 6; no 200 bonus; advances
  /// capped to available net with automatic carry-over.
  Future<void> calculateWeeklyPay(
    User? user,
    String staffId,
    int year,
    int month,
    int week,
  ) async {
    PermissionValidator.requirePermission(
      user,
      Permission.manageSalaries,
      'حساب الرواتب',
    );
    final staff = await _dao.getStaffById(staffId);
    if (staff == null) return;
    if (staff.payFrequency != 'weekly') {
      throw Exception(
        'الموظف ليس على دورة أسبوعية (الحالية: ${staff.payFrequency})',
      );
    }
    final weeklySalary = staff.weeklySalary;
    if (weeklySalary == null || weeklySalary <= 0) {
      throw Exception('حدد الأجر الأسبوعي للموظف أولاً');
    }
    final bounds = weekBounds(year, month, week);
    final period = '$year-${month.toString().padLeft(2, '0')}-W$week';
    await calculatePeriodPay(
      staffId: staffId,
      payrollPeriod: period,
      periodStart: bounds.$1,
      periodEnd: bounds.$2,
      baseSalary: weeklySalary,
      dailyDivisor: 6, // locked: اليوم = الأسبوعي ÷ 6
      applyCommitmentBonus: false, // locked: مكافأة الـ200 لا تنطبق أسبوعياً
      capAdvancesToNet: true, // locked: سقف السلفة + ترحيل الباقي
    );
  }

  DateTime _getPeriodStart(String period) {
    // Parse period like "2024-01" or "2024-01-W1"
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    if (parts.length > 2 && parts[2].startsWith('W')) {
      final week = int.parse(parts[2].substring(1));
      return weekBounds(year, month, week).$1;
    }

    return DateTime(year, month, 1);
  }

  DateTime _getPeriodEnd(String period) {
    final parts = period.split('-');

    if (parts.length > 2 && parts[2].startsWith('W')) {
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final week = int.parse(parts[2].substring(1));
      return weekBounds(year, month, week).$2;
    }

    final start = _getPeriodStart(period);
    return DateTime(start.year, start.month + 1, 0); // Last day of month
  }

  // PERFORMANCE MANAGEMENT

  Future<void> createPerformanceReview(
    User? user, {
    required String staffId,
    required String reviewPeriod,
    required String reviewerId,
    required double overallRating,
    required double workQualityRating,
    required double productivityRating,
    required double teamworkRating,
    required double punctualityRating,
    required double initiativeRating,
    String? strengths,
    String? weaknesses,
    String? goals,
    String? recommendations,
    String? actionPlan,
    DateTime? nextReviewDate,
  }) async {
    PermissionValidator.requirePermission(
      user,
      Permission.editEmployee,
      'تقييم أداء',
    );
    await _dao.addPerformanceReview(
      PerformanceReviewsCompanion.insert(
        staffId: staffId,
        reviewPeriod: reviewPeriod,
        reviewDate: DateTime.now(),
        reviewerId: reviewerId,
        overallRating: overallRating,
        workQualityRating: workQualityRating,
        productivityRating: productivityRating,
        teamworkRating: teamworkRating,
        punctualityRating: punctualityRating,
        initiativeRating: initiativeRating,
        strengths: Value(strengths ?? ''),
        weaknesses: Value(weaknesses ?? ''),
        goals: Value(goals ?? ''),
        recommendations: Value(recommendations ?? ''),
        actionPlan: Value(actionPlan ?? ''),
        nextReviewDate: Value(nextReviewDate),
        status: 'submitted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<double> getAverageRating(String staffId) async {
    final reviews = await _dao.getReviewsByStaff(staffId);
    if (reviews.isEmpty) return 0.0;

    final totalRating = reviews.fold<double>(
      0,
      (sum, review) => sum + review.overallRating,
    );
    return totalRating / reviews.length;
  }
}

/// تفصيل المستحق للصرف لفترة: المستحق (نشطون غير مدفوعين) +
/// المدفوع مسبقاً (مستبعد) + المنتهية خدمتهم (مستبعد) + رقم المستند التالي.
class DisbursementBreakdown {
  final List<Payroll> payable;
  final int paidCount;
  final double paidTotal;
  final int excludedCount;
  final double excludedTotal;
  final String voucherNo;

  const DisbursementBreakdown({
    required this.payable,
    required this.paidCount,
    required this.paidTotal,
    required this.excludedCount,
    required this.excludedTotal,
    required this.voucherNo,
  });

  int get payableCount => payable.length;
  double get payableTotal => payable.fold(0.0, (s, p) => s + p.netSalary);
  int get payableCalculated =>
      payable.where((p) => p.status == 'calculated').length;
}

class AttendanceSummary {
  final int totalDays;
  final int presentDays;
  final int absentDays;
  final int leaveDays;
  final int lateDays;
  final double totalHours;
  final double totalOvertime;
  final int totalLateMinutes;
  final int totalEarlyMinutes;
  final int totalLateExcusedMinutes;
  final int totalEarlyExcusedMinutes;
  final double totalLateHours;
  final double totalPermissionHours;

  AttendanceSummary({
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.lateDays,
    required this.totalHours,
    required this.totalOvertime,
    this.totalLateMinutes = 0,
    this.totalEarlyMinutes = 0,
    this.totalLateExcusedMinutes = 0,
    this.totalEarlyExcusedMinutes = 0,
    this.totalLateHours = 0,
    this.totalPermissionHours = 0,
  });

  double get totalEarlyHours => totalEarlyMinutes / 60.0;
  double get totalLateExcusedHours => totalLateExcusedMinutes / 60.0;
  double get totalEarlyExcusedHours => totalEarlyExcusedMinutes / 60.0;

  double get attendanceRate => totalDays > 0 ? presentDays / totalDays : 0.0;

  double get averageHoursPerDay =>
      presentDays > 0 ? totalHours / presentDays : 0.0;
}
