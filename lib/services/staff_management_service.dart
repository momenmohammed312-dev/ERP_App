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
    PermissionValidator.requirePermission(user, Permission.createEmployee, 'إضافة موظف');
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
    bool? useDefaultSchedule,
    String? workScheduleStart,
    String? workScheduleEnd,
    String? workDays,
    String? weekendDay,
  }) async {
    PermissionValidator.requirePermission(user, Permission.editEmployee, 'تعديل موظف');
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
    PermissionValidator.requirePermission(user, Permission.editEmployee, 'إنهاء خدمة موظف');
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
    final db = _db;
    if (db != null) {
      try {
        final engine = AttendanceCalculationEngine(
          db,
          db.attendanceDeviceDao,
          _dao,
        );
        status = await engine.processCheckIn(staffId);
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
    PermissionValidator.requirePermission(user, Permission.manageAttendance, 'حذف سجل حضور');
    await _dao.deleteAttendanceByDate(staffId, date);
  }

  /// Deletes all imported attendance for a staff (source='import') — لإزالة الدوبلر
  Future<int> deleteImportedForStaff(User? user, String staffId) async {
    PermissionValidator.requirePermission(user, Permission.manageAttendance, 'حذف حضور مستورد');
    return await _dao.deleteAttendanceByStaffAndSource(staffId, 'import');
  }

  /// حذف نهائي للموظف وكل سجلاته (حضور، سلف، رواتب، إجازات، جزاءات) — لإزالة الاسم من كل السجلات
  Future<void> deleteStaffCompletely(User? user, String staffId) async {
    PermissionValidator.requirePermission(user, Permission.editEmployee, 'حذف موظف');
    final db = _dao.attachedDatabase;
    await db.transaction(() async {
      await _dao.deleteStaff(staffId);
      await (db.delete(db.attendanceTable)..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(db.staffAdvances)..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(db.payrollTable)..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(db.vacations)..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(db.rewardsPenalties)..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(db.performanceReviews)..where((t) => t.staffId.equals(staffId))).go();
      await (db.delete(db.staffDocuments)..where((t) => t.staffId.equals(staffId))).go();
      // بصمة
      try {
        await (db.delete(db.staffBiometricMappings)..where((t) => t.staffId.equals(staffId))).go();
      } catch (_) {}
    });
  }

  Future<void> recordManualOverride(
    User? user,
    String staffId, {
    required DateTime date,
    required String status,
    required String reason,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
  }) async {
    PermissionValidator.requirePermission(user, Permission.manageAttendance);
    if (reason.trim().isEmpty) {
      throw Exception('Reason is required for manual override');
    }

    final entry = AttendanceTableCompanion.insert(
      staffId: staffId,
      date: date,
      status: status,
      checkInTime: Value(checkInTime),
      checkOutTime: Value(checkOutTime),
      notes: Value(notes),
      source: const Value('admin_override'),
      overrideReason: Value(reason),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final todayRecords = await _dao.getAttendanceOnDate(staffId, date);

    if (todayRecords.isNotEmpty) {
      final updated = todayRecords.first.copyWith(
        status: status,
        checkInTime: Value(checkInTime),
        checkOutTime: Value(checkOutTime),
        notes: Value(notes),
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
    String? notes,
    String source = 'manual',
  }) async {
    // خصم ساعة الراحة من ساعات العمل المحسوبة يدوياً (من 8 لـ5 = 8 ساعات)
    var finalWorkingHours = workingHours;
    if (finalWorkingHours != null && checkOutTime != null && checkInTime != null) {
      final breakMinutes = await _getBreakMinutes();
      final breakHrs = breakMinutes / 60.0;
      final raw = checkOutTime.difference(checkInTime).inMinutes / 60.0;
      final computed = raw - breakHrs;
      finalWorkingHours = computed < 0 ? 0 : computed;
    }
    final entry = AttendanceTableCompanion.insert(
      staffId: staffId,
      date: date,
      status: status,
      checkInTime: Value(checkInTime),
      checkOutTime: Value(checkOutTime),
      workingHours: Value(finalWorkingHours),
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
        notes: Value(notes),
        source: Value(source),
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(updated);
    } else {
      await _dao.addAttendance(entry);
    }
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
        checkInTime: clearTimes ? const Value(null) : Value(existing.first.checkInTime),
        checkOutTime: clearTimes ? const Value(null) : Value(existing.first.checkOutTime),
        workingHours: clearTimes ? const Value(null) : Value(existing.first.workingHours),
        notes: Value(notes),
        source: Value(source),
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(rec);
    } else {
      await _dao.addAttendance(AttendanceTableCompanion.insert(
        staffId: staffId,
        date: dateOnly,
        status: status,
        excused: Value(excused),
        excusedHours: Value(excusedHours),
        notes: Value(notes),
        source: Value(source),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// إلغاء الإذن ليوم واحد — يرجع excused=false و excusedHours=0
  Future<void> clearExcusedDay(String staffId, DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final existing = await _dao.getAttendanceOnDate(staffId, dateOnly);
    if (existing.isEmpty) return;
    final rec = existing.first.copyWith(excused: false, excusedHours: 0, updatedAt: DateTime.now());
    await _dao.updateAttendance(rec);
  }

  /// إلغاء الإذن لفترة — يرجع كل الأيام في الفترة إلى بدون إذن
  Future<int> clearExcusedPeriod(String staffId, DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    int count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final existing = await _dao.getAttendanceOnDate(staffId, d);
      if (existing.isEmpty) continue;
      if (!existing.first.excused && existing.first.excusedHours == 0) continue;
      final rec = existing.first.copyWith(excused: false, excusedHours: 0, updatedAt: DateTime.now());
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

    // لجمع دقائق التأخير/انصراف مبكر نحتاج جدول العمل
    ScheduleConfig? schedule;
    final db = _db;
    if (db != null) {
      try {
        final engine = AttendanceCalculationEngine(db, db.attendanceDeviceDao, _dao);
        schedule = await engine.getScheduleForStaff(staffId);
      } catch (_) {}
    }

    bool isLateByTime(Attendance r) {
      if (r.checkInTime == null || schedule == null) return false;
      if (r.excused && r.excusedHours <= 0) return false; // بإذن كامل — لا يُحسب تأخير
      final ciMin = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
      final graceEnd = schedule.workStartMinutesSinceMidnight + schedule.gracePeriodMinutes;
      return ciMin > graceEnd;
    }

    // يخصم ساعات الإذن المسموح (excusedHours) من الدقائق الفعلية للمخالفة —
    // المطلوب حالياً: ساعات الإذن نفسها تُخصم بسعر عادي (1x) + الزيادة بخصم مضاعف
    // لذا نحسب الاثنين منفصلين: excusedUsed (يُخصم 1x) و excess (يُخصم بمضاعف)
    int _excessMinutes(int actualMinutes, Attendance r) {
      if (!r.excused) return actualMinutes; // بدون إذن — كله excess
      final allowedMinutes = (r.excusedHours * 60).round();
      if (allowedMinutes <= 0) return 0; // بإذن كامل بلا ساعات — لا excess
      final result = actualMinutes - allowedMinutes;
      return result < 0 ? 0 : result;
    }

    int _excusedUsedMinutes(int actualMinutes, Attendance r) {
      if (!r.excused) return 0; // بدون إذن — لا يوجد جزء مأذون
      final allowedMinutes = (r.excusedHours * 60).round();
      if (allowedMinutes <= 0) return 0; // بإذن كامل بلا ساعات محددة — مجاني بالكامل
      return actualMinutes < allowedMinutes ? actualMinutes : allowedMinutes;
    }

    for (final record in attendanceRecords) {
      // تحديد التأخير دفاعياً من الوقت حتى لو status مخزون خطأً كـ present (استيراد قديم)
      final effectiveIsLate = (record.status == 'late' || (record.status == 'present' && isLateByTime(record)));
      switch (record.status) {
        case 'present':
          if (effectiveIsLate) {
            lateDays++;
            presentDays++;
            final ciMin = record.checkInTime!.hour * 60 + record.checkInTime!.minute;
            final graceEnd = schedule!.workStartMinutesSinceMidnight + schedule.gracePeriodMinutes;
            if (ciMin > graceEnd) {
              final actual = ciMin - graceEnd;
              totalLateMinutes += _excessMinutes(actual, record);
              totalLateExcusedMinutes += _excusedUsedMinutes(actual, record);
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
          presentDays++; // Late counts as present
          // احتساب دقائق التأخير الفعلية بعد فترة السماح — ساعات الإذن تُخصم 1x والزيادة بمضاعف
          if (record.checkInTime != null && schedule != null) {
            if (record.excused && record.excusedHours <= 0) {
              // بإذن كامل مجاني — لا يُحسب lateDays ولا خصم
            } else {
              lateDays++;
              final ciMin = record.checkInTime!.hour * 60 + record.checkInTime!.minute;
              final graceEnd = schedule.workStartMinutesSinceMidnight + schedule.gracePeriodMinutes;
              if (ciMin > graceEnd) {
                final actual = ciMin - graceEnd;
                totalLateMinutes += _excessMinutes(actual, record);
                totalLateExcusedMinutes += _excusedUsedMinutes(actual, record);
              }
            }
          }
          break;
        case 'early_leave':
          if (!record.excused && record.checkInTime != null && record.checkOutTime != null && schedule != null) {
            // تحقق من كونه بدري فعلياً (checkOut قبل نهاية الدوام)
            final coMin = record.checkOutTime!.hour * 60 + record.checkOutTime!.minute;
            final endMin = schedule.workEndMinutesSinceMidnight;
            if (coMin < endMin) lateDays++;
          }
          presentDays++; // يُحسب كحضور مع بدري (بإذن = بدون خصم)
          break;
      }

      // انصراف مبكر: يحسب لأي سجل فيه checkOut قبل نهاية الدوام — ساعات الإذن 1x والزيادة بمضاعف
      if (record.checkOutTime != null && schedule != null) {
        final coMin = record.checkOutTime!.hour * 60 + record.checkOutTime!.minute;
        final endMin = schedule.workEndMinutesSinceMidnight;
        if (coMin < endMin) {
          final actual = endMin - coMin;
          // even if excused fully with 0 hours, both helpers return 0 correctly
          if (record.excused && record.excusedHours <= 0) {
            // بإذن كامل مجاني — لا شيء يُخصم
          } else {
            totalEarlyMinutes += _excessMinutes(actual, record);
            totalEarlyExcusedMinutes += _excusedUsedMinutes(actual, record);
          }
        }
      }

      totalHours += record.workingHours ?? 0.0;
      totalOvertime += record.overtimeHours;
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
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'طلب سلفة');
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
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'اعتماد سلفة');
    await _dao.approveAdvance(advanceId, user?.fullName ?? 'admin');
  }

  Future<void> rejectAdvance(User? user, int advanceId, String reason) async {
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'رفض سلفة');
    await _dao.rejectAdvance(advanceId, user?.fullName ?? 'admin', reason);
  }

  // PAYROLL MANAGEMENT

  Future<void> calculatePayroll(User? user, String staffId, String payrollPeriod) async {
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'حساب الرواتب');
    final staff = await _dao.getStaffById(staffId);
    if (staff == null) return;

    final periodStart = _getPeriodStart(payrollPeriod);
    final periodEnd = _getPeriodEnd(payrollPeriod);

    // توليد الغياب تلقائياً لكل يوم في الفترة قبل الحساب — يحترم الجمعة/الإجازة
    // مهم: لا نولّد غياب لأيام مستقبلية (بعد اليوم) — وإلا يظهر غياب 30 يوم مقدماً كما في الصورة
    final dbForAbsence = _dao.attachedDatabase;
    try {
      // تنظيف غياب مستقبلي قديم اتولد بالغلط قبل الإصلاح
      try { await _dao.deleteFutureAutoAbsences(); } catch (_) {}
      final engine = AttendanceCalculationEngine(dbForAbsence, dbForAbsence.attendanceDeviceDao, _dao);
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final effectiveEnd = periodEnd.isAfter(today) ? today : periodEnd;
      for (var d = DateTime(periodStart.year, periodStart.month, periodStart.day);
          !d.isAfter(DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day));
          d = d.add(const Duration(days: 1))) {
        await engine.generateAbsencesForDate(d);
      }
    } catch (_) {}
    // Get attendance data
    final attendanceSummary = await getAttendanceSummary(
      staffId,
      periodStart,
      periodEnd,
    );

    // Get advances to deduct (approved or paid advances, respecting installments)
    final advances = await _dao.getAdvancesByStaff(staffId);
    final eligibleAdvances = advances.where(
      (a) => (a.status == 'approved' || a.status == 'paid'),
    ).toList();

    double totalAdvances = 0.0;
    for (final a in eligibleAdvances) {
      if (a.installmentMonths != null &&
          a.installmentMonths! > 1 &&
          a.monthlyDeduction != null &&
          a.monthlyDeduction! > 0) {
        totalAdvances += a.monthlyDeduction!;
      } else {
        totalAdvances += a.amount;
      }
    }

    // Get rewards and penalties for the period
    final db = _dao.attachedDatabase;

    // Check if payroll was already calculated or paid for this period
    final existingPayroll = await (db.select(db.payrollTable)
      ..where((t) => t.staffId.equals(staffId) & t.payrollPeriod.equals(payrollPeriod))
    ).getSingleOrNull();

    if (existingPayroll != null) {
      if (existingPayroll.status == 'paid') {
        throw Exception('تم صرف راتب هذه الفترة بالفعل ولا يمكن إعادة احتسابه');
      }
      // Remove old calculated record so fresh calculations replace it cleanly
      await (db.delete(db.payrollTable)..where((t) => t.id.equals(existingPayroll.id))).go();
    }

    final allRewardsPenalties = await (db.select(db.rewardsPenalties)
      ..where((t) => t.staffId.equals(staffId) & t.status.equals('active'))
    ).get();
    final periodRewards = allRewardsPenalties.where((rp) =>
      rp.effectiveDate.isAfter(periodStart.subtract(const Duration(days: 1))) &&
      rp.effectiveDate.isBefore(periodEnd.add(const Duration(days: 1))),
    ).toList();

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

    final basicSalary = staff.basicSalary;
    int workingDaysInPeriod = 0;
    try {
      final engTmp = AttendanceCalculationEngine(db, db.attendanceDeviceDao, _dao);
      for (var d = DateTime(periodStart.year, periodStart.month, periodStart.day);
          !d.isAfter(DateTime(periodEnd.year, periodEnd.month, periodEnd.day));
          d = d.add(const Duration(days: 1))) {
        final sched = await engTmp.getScheduleForStaff(staffId);
        if (engTmp.isWorkDay(d, sched)) workingDaysInPeriod++;
      }
    } catch (_) {}
    if (workingDaysInPeriod == 0) workingDaysInPeriod = 30;
    // Auto penalties from attendance settings — يطبق على كل بصمة/حضور محسوب مسبقاً
    // يدعم: late بالساعات (per_hour) أو بالمرة (legacy per late), وغياب بمبلغ ثابت أو مضاعف يوم
    try {
      final latePerHourRow = await (db.select(db.attendanceSettings)
            ..where((t) => t.settingKey.equals('late_penalty_per_hour')))
          .getSingleOrNull();
      final lateAmountRow = await (db.select(db.attendanceSettings)
            ..where((t) => t.settingKey.equals('late_penalty_amount')))
          .getSingleOrNull();
      final absenceRow = await (db.select(db.attendanceSettings)
            ..where((t) => t.settingKey.equals('absence_penalty_amount')))
          .getSingleOrNull();
      final absenceMultRow = await (db.select(db.attendanceSettings)
            ..where((t) => t.settingKey.equals('absence_penalty_days_multiplier')))
          .getSingleOrNull();
      final latePerHour = double.tryParse(latePerHourRow?.settingValue ?? '0') ?? 0;
      final latePerOccurrence = double.tryParse(lateAmountRow?.settingValue ?? '0') ?? 0;
      final absencePerDay = double.tryParse(absenceRow?.settingValue ?? '0') ?? 0;
      final absenceMult = double.tryParse(absenceMultRow?.settingValue ?? '1') ?? 1.0;
      final earlyRow = await (db.select(db.attendanceSettings)
            ..where((t) => t.settingKey.equals('early_leave_penalty_per_hour')))
          .getSingleOrNull();
      final earlyPerHour = double.tryParse(earlyRow?.settingValue ?? '0') ?? 0;

      double autoLatePenalty = 0;
      final hourlyRate = staff.hourlyRate ?? (basicSalary / 30 / 8);
      // ساعات الإذن المأذونة تُخصم بسعر عادي (1x) + الزيادة بمضاعف — مثال 3س تأخير وإذن 2س = 2س*1x + 1س*1.5x
      final excusedLateDeduction = attendanceSummary.totalLateExcusedHours * hourlyRate;
      if (latePerHour > 0 && attendanceSummary.totalLateHours > 0) {
        // latePerHour الآن مضاعف (1.5 = ساعة ونص) وليس مبلغ
        autoLatePenalty = attendanceSummary.totalLateHours * hourlyRate * latePerHour + excusedLateDeduction;
      } else if (latePerOccurrence > 0) {
        autoLatePenalty = attendanceSummary.lateDays * latePerOccurrence + excusedLateDeduction;
      } else {
        // حتى بدون مضاعف، ساعات الإذن نفسها تُخصم كغياب جزئي بسعر عادي
        autoLatePenalty = excusedLateDeduction;
      }
      double autoAbsencePenalty = 0;
      if (absencePerDay > 0) {
        autoAbsencePenalty = attendanceSummary.absentDays * absencePerDay;
      } else if (absenceMult != 1.0 || absenceMult > 0) {
        final daily = basicSalary / 30.0;
        autoAbsencePenalty = attendanceSummary.absentDays * daily * absenceMult;
      }
      double autoEarlyPenalty = 0;
      final excusedEarlyDeduction = attendanceSummary.totalEarlyExcusedHours * hourlyRate;
      if (earlyPerHour > 0 && attendanceSummary.totalEarlyHours > 0) {
        autoEarlyPenalty = attendanceSummary.totalEarlyHours * hourlyRate * earlyPerHour + excusedEarlyDeduction;
      } else {
        autoEarlyPenalty = excusedEarlyDeduction;
      }
      penaltiesTotal += autoLatePenalty + autoAbsencePenalty + autoEarlyPenalty;
    } catch (_) {
      // لو جدول الإعدادات غير موجود أو فشل القراءة — تجاهل الخصم التلقائي
    }

    // Calculate payroll (basicSalary already defined) — workingDaysInPeriod محسوب مسبقاً
    // الوقت الإضافي يُحسب بمضاعف من الإعدادات (1.5x افتراضياً)
    final otMultiplierRow = await (db.select(db.attendanceSettings)
          ..where((t) => t.settingKey.equals('overtime_rate_multiplier')))
        .getSingleOrNull();
    final overtimeMultiplier =
        double.tryParse(otMultiplierRow?.settingValue ?? '1.5') ?? 1.5;
    final hourlyRateForOT = staff.hourlyRate ?? basicSalary / 30 / 8;
    final overtimePay =
        attendanceSummary.totalOvertime * hourlyRateForOT * overtimeMultiplier;

    final deductions = totalAdvances + penaltiesTotal;

    final netSalary = basicSalary + overtimePay + allowancesTotal + rewardsTotal - deductions;

    await db.into(db.payrollTable).insert(
          PayrollTableCompanion.insert(
            staffId: staffId,
            payrollPeriod: payrollPeriod,
            periodStart: periodStart,
            periodEnd: periodEnd,
            basicSalary: basicSalary,
            overtimeHours: Value(attendanceSummary.totalOvertime),
            overtimeRate: Value(hourlyRateForOT * overtimeMultiplier),
            overtimePay: Value(overtimePay),
            allowances: Value(allowancesTotal),
            deductions: Value(deductions),
            advances: Value(totalAdvances),
            netSalary: netSalary,
            workingDays: Value(workingDaysInPeriod),
            presentDays: Value(attendanceSummary.presentDays),
            absentDays: Value(attendanceSummary.absentDays),
            leaveDays: Value(attendanceSummary.leaveDays),
            rewardsTotal: Value(rewardsTotal),
            penaltiesTotal: Value(penaltiesTotal),
            status: 'calculated',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> payAdvance(User? user, int advanceId, String paymentMethod) async {
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'صرف سلفة');
    final db = _dao.attachedDatabase;
    final isDayOpen = await db.dayDao.isDayOpen();
    if (!isDayOpen) {
      throw Exception('يجب فتح يوم مالي أولاً');
    }
    return db.transaction(() async {
      final advance = await (db.select(db.staffAdvances)..where((t) => t.id.equals(advanceId))).getSingleOrNull();
      if (advance == null || advance.status == 'paid') return;

      await (db.update(db.staffAdvances)..where((t) => t.id.equals(advanceId))).write(
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

  Future<void> payPayroll(User? user, int payrollId, String paymentMethod) async {
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'صرف رواتب');
    final db = _dao.attachedDatabase;
    final isDayOpen = await db.dayDao.isDayOpen();
    if (!isDayOpen) {
      throw Exception('يجب فتح يوم مالي أولاً');
    }
    return db.transaction(() async {
      final payroll = await (db.select(db.payrollTable)..where((t) => t.id.equals(payrollId))).getSingleOrNull();
      if (payroll == null || payroll.status == 'paid') return;

      await (db.update(db.payrollTable)..where((t) => t.id.equals(payrollId))).write(
        PayrollTableCompanion(
          status: const Value('paid'),
          paymentDate: Value(DateTime.now()),
          paymentMethod: Value(paymentMethod),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final desc = 'راتب موظف: ${payroll.staffId} للفترة ${payroll.payrollPeriod}';
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

      await (db.update(db.payrollTable)..where((t) => t.id.equals(payrollId))).write(
        PayrollTableCompanion(
          expenseRefId: Value(expenseId),
        ),
      );

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

  DateTime _getPeriodStart(String period) {
    // Parse period like "2024-01" or "2024-01-W1"
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    if (parts.length > 2 && parts[2].startsWith('W')) {
      final week = int.parse(parts[2].substring(1));
      final firstDay = DateTime(year, month, 1);
      final startOfWeek = firstDay.add(Duration(days: (week - 1) * 7));
      return startOfWeek;
    }

    return DateTime(year, month, 1);
  }

  DateTime _getPeriodEnd(String period) {
    final start = _getPeriodStart(period);
    final parts = period.split('-');

    if (parts.length > 2 && parts[2].startsWith('W')) {
      return start.add(const Duration(days: 6));
    }

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
    PermissionValidator.requirePermission(user, Permission.editEmployee, 'تقييم أداء');
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
  });

  double get totalLateHours => totalLateMinutes / 60.0;
  double get totalEarlyHours => totalEarlyMinutes / 60.0;
  double get totalLateExcusedHours => totalLateExcusedMinutes / 60.0;
  double get totalEarlyExcusedHours => totalEarlyExcusedMinutes / 60.0;

  double get attendanceRate => totalDays > 0 ? presentDays / totalDays : 0.0;

  double get averageHoursPerDay =>
      presentDays > 0 ? totalHours / presentDays : 0.0;
}
