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

  Future<String> addNewStaff(
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
    return staffId;
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

  /// Restored old rule: worked + overtime hours are always derived from the
  /// recorded times via the engine (schedule-aware). Falls back to a raw
  /// span minus 8 standard hours when the DB/engine is unavailable.
  Future<({double workingHours, double overtimeHours})> _calcWorkedHours(
    String staffId,
    DateTime checkInTime,
    DateTime checkOutTime,
  ) async {
    final repoDb = _db;
    if (repoDb != null) {
      try {
        final engine = AttendanceCalculationEngine(
          repoDb,
          repoDb.attendanceDeviceDao,
          _dao,
        );
        final calc = await engine.processCheckOut(
          staffId,
          checkInTime: checkInTime,
          checkOutTime: checkOutTime,
        );
        return (
          workingHours: calc.workingHours,
          overtimeHours: calc.overtimeHours,
        );
      } catch (_) {}
    }
    final raw = checkOutTime.difference(checkInTime).inMinutes / 60.0;
    if (raw <= 0) return (workingHours: 0.0, overtimeHours: 0.0);
    final ot = raw - 8.0;
    return (
      workingHours: raw <= 8.0 ? raw : 8.0,
      overtimeHours: ot > 0 ? ot : 0.0,
    );
  }

  /// Restored old rule (recomputeOvertimeForPeriod): recalculate worked +
  /// overtime hours for every row in [start, end] that has both times.
  /// Skips admin overrides (explicit managerial decision) and days inside a
  /// paid payroll period. Everything runs in one transaction (atomic).
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
    final e = DateTime(end.year, end.month, end.day).add(
      const Duration(days: 1),
    );

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
        final pe = DateTime(p.periodEnd.year, p.periodEnd.month, p.periodEnd.day);
        if (!d.isBefore(ps) && !d.isAfter(pe)) return true;
      }
      return false;
    }

    int recomputed = 0;
    int skipped = 0;
    await db.transaction(() async {
      for (final r in rows) {
        if (r.checkInTime == null ||
            r.checkOutTime == null ||
            r.source == 'admin_override' ||
            inPaidPeriod(r.date)) {
          skipped++;
          continue;
        }
        final calc = await _calcWorkedHours(
          staffId,
          r.checkInTime!,
          r.checkOutTime!,
        );
        await _dao.updateAttendance(
          r.copyWith(
            workingHours: Value(calc.workingHours),
            overtimeHours: calc.overtimeHours,
            updatedAt: DateTime.now(),
          ),
        );
        recomputed++;
      }
    });
    return (recomputed: recomputed, skipped: skipped);
  }

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

  Future<void> recordManualOverride(
    User? user,
    String staffId, {
    required DateTime date,
    required String status,
    required String reason,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
    String? leaveType,
  }) async {
    PermissionValidator.requirePermission(user, Permission.manageAttendance);
    if (reason.trim().isEmpty) {
      throw Exception('Reason is required for manual override');
    }

    // Restored intent rule: an override that carries an excuse (explicit
    // leaveType, or إذن/تصريح written in the notes) but keeps a plain
    // present/late status is coerced to excused/excused_late — otherwise the
    // permission is saved yet never counted anywhere ("عملت إذن ومسمّعش").
    String finalStatus = status;
    String? finalLeaveType = leaveType;
    final notesText = notes ?? '';
    final mentionsExcuse =
        notesText.contains('إذن') ||
        notesText.contains('اذن') ||
        notesText.contains('تصريح');
    if (finalStatus == 'present' &&
        (finalLeaveType?.isNotEmpty == true || mentionsExcuse)) {
      finalStatus = 'excused';
      finalLeaveType ??= 'other';
    } else if (finalStatus == 'late' &&
        (finalLeaveType?.isNotEmpty == true || mentionsExcuse)) {
      finalStatus = 'excused_late';
      finalLeaveType ??= 'other';
    }

    // Restored old rule: an override with both times also refreshes the
    // derived worked/overtime hours instead of leaving stale values.
    double? finalWorkingHours;
    double? finalOvertimeHours;
    if (checkInTime != null && checkOutTime != null) {
      final calc = await _calcWorkedHours(staffId, checkInTime, checkOutTime);
      finalWorkingHours = calc.workingHours;
      finalOvertimeHours = calc.overtimeHours;
    }

    final entry = AttendanceTableCompanion.insert(
      staffId: staffId,
      date: date,
      status: finalStatus,
      checkInTime: Value(checkInTime),
      checkOutTime: Value(checkOutTime),
      workingHours: finalWorkingHours == null
          ? const Value.absent()
          : Value(finalWorkingHours),
      overtimeHours: finalOvertimeHours == null
          ? const Value.absent()
          : Value(finalOvertimeHours),
      notes: Value(notes),
      leaveType: Value(finalLeaveType),
      source: const Value('admin_override'),
      overrideReason: Value(reason),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // If an entry already exists for this date, we should update it, otherwise add.
    final existing = await _dao.getAttendanceByStaff(staffId, startDate: date, endDate: date.add(const Duration(days: 1)));
    final todayRecords = existing.where((a) => a.date == date).toList();

    if (todayRecords.isNotEmpty) {
      final current = todayRecords.first;
      final updated = current.copyWith(
        status: finalStatus,
        checkInTime: Value(checkInTime),
        checkOutTime: Value(checkOutTime),
        workingHours: finalWorkingHours == null
            ? Value(current.workingHours)
            : Value(finalWorkingHours),
        overtimeHours: finalOvertimeHours ?? current.overtimeHours,
        notes: Value(notes),
        leaveType: Value(finalLeaveType),
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
    String? leaveType,
    String source = 'manual',
  }) async {
    // Restored old rule: worked/overtime hours always follow the times via
    // the engine — explicit values win, missing ones are derived so overtime
    // ("إضافي") is never silently left at zero on manual saves.
    double? finalWorkingHours = workingHours;
    double? finalOvertimeHours = overtimeHours;
    if (checkInTime != null &&
        checkOutTime != null &&
        (finalWorkingHours == null || finalOvertimeHours == null)) {
      final calc = await _calcWorkedHours(staffId, checkInTime, checkOutTime);
      finalWorkingHours ??= calc.workingHours;
      finalOvertimeHours ??= calc.overtimeHours;
    }

    final entry = AttendanceTableCompanion.insert(
      staffId: staffId,
      date: date,
      status: status,
      checkInTime: Value(checkInTime),
      checkOutTime: Value(checkOutTime),
      workingHours: Value(finalWorkingHours),
      overtimeHours: finalOvertimeHours == null
          ? const Value.absent()
          : Value(finalOvertimeHours),
      notes: Value(notes),
      leaveType: Value(leaveType),
      source: Value(source),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final existing = await _dao.getAttendanceByStaff(
      staffId,
      startDate: date,
      endDate: date.add(const Duration(days: 1)),
    );
    final todayRecords = existing.where((a) => a.date == date).toList();

    if (todayRecords.isNotEmpty) {
      final current = todayRecords.first;
      final updated = current.copyWith(
        status: status,
        checkInTime: Value(checkInTime),
        checkOutTime: Value(checkOutTime),
        workingHours: finalWorkingHours == null
            ? Value(current.workingHours)
            : Value(finalWorkingHours),
        overtimeHours: finalOvertimeHours ?? current.overtimeHours,
        notes: Value(notes),
        leaveType: Value(leaveType),
        source: Value(source),
        updatedAt: DateTime.now(),
      );
      await _dao.updateAttendance(updated);
    } else {
      await _dao.addAttendance(entry);
    }
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

    // Restored effective-late rule: a 'present' row whose check-in is past
    // grace still counts as late (days + minutes), so payroll fines and the
    // attendance screen agree. Falls back to status-only when the engine
    // or schedule is unavailable.
    ScheduleConfig? schedule;
    final repoDb = _db;
    if (repoDb != null) {
      try {
        final engine = AttendanceCalculationEngine(
          repoDb,
          repoDb.attendanceDeviceDao,
          _dao,
        );
        schedule = await engine.getScheduleForStaff(staffId);
      } catch (_) {}
    }

    int lateMinutesOf(Attendance r) {
      if (r.status == 'excused' || r.status == 'excused_late') return 0;
      if (r.checkInTime == null || schedule == null) return 0;
      final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
      final graceEnd =
          schedule.workStartMinutesSinceMidnight + schedule.gracePeriodMinutes;
      if (ci <= graceEnd) return 0;
      return ci - graceEnd;
    }

    for (final record in attendanceRecords) {
      switch (record.status) {
        case 'present':
          presentDays++;
          final lm = lateMinutesOf(record);
          if (lm > 0) {
            lateDays++;
            totalLateMinutes += lm;
          }
          break;
        case 'absent':
          absentDays++;
          break;
        case 'leave':
          leaveDays++;
          break;
        case 'late':
          lateDays++;
          presentDays++; // Late counts as present
          totalLateMinutes += lateMinutesOf(record);
          break;
        // Bug 5: إذن — excused days count as present, never as late,
        // so the flat late fine (lateDays × setting) skips them while
        // HR still sees them distinctly in the attendance list.
        case 'excused':
        case 'excused_late':
          presentDays++;
          break;
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

  // PAYROLL MANAGEMENT

  /// Bug 4(b): flat fine per late instance, from the `late_penalty_amount`
  /// attendance setting. Safe default 0 — a missing or unreadable setting
  /// leaves payroll exactly as before (never breaks a calculation).
  Future<double> _latePenaltyPerInstance() async {
    try {
      final db = _dao.attachedDatabase;
      final row = await (db.select(db.attendanceSettings)
            ..where((t) => t.settingKey.equals('late_penalty_amount')))
          .getSingleOrNull();
      if (row == null) return 0.0;
      final v = double.tryParse(row.settingValue) ?? 0.0;
      return v < 0 ? 0.0 : v;
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> calculatePayroll(User? user, String staffId, String payrollPeriod) async {
    PermissionValidator.requirePermission(user, Permission.manageSalaries, 'حساب الرواتب');
    final staff = await _dao.getStaffById(staffId);
    if (staff == null) return;

    final periodStart = _getPeriodStart(payrollPeriod);
    final periodEnd = _getPeriodEnd(payrollPeriod);

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

    // Calculate payroll — base depends on employment type (restored rules):
    // - daily: day wage × present days in the period (present + late + excused)
    // - weekly / full_time / part_time / contract: basicSalary as-is for the
    //   chosen period (weekly staff pick a W-period, monthly staff a month).
    final isWeeklyPeriod = payrollPeriod.contains('-W');
    double basicSalary = staff.basicSalary;
    if (staff.employmentType == 'daily') {
      basicSalary = staff.basicSalary * attendanceSummary.presentDays;
    }
    // Hourly base always derives from the single-unit wage, not the
    // period total (daily total would inflate it by present days).
    final hourlyBase = staff.hourlyRate ??
        (staff.employmentType == 'daily'
            ? staff.basicSalary / 8
            : isWeeklyPeriod
                ? staff.basicSalary / 48
                : staff.basicSalary / 160);
    final overtimePay = attendanceSummary.totalOvertime * hourlyBase;

    // Bug 4(b): flat fine per late day (explicit 'late' rows plus 'present'
    // rows past grace — see getAttendanceSummary). Excused rows never count.
    // Default setting 0 → identical to the old behavior.
    final lateDeduction =
        attendanceSummary.lateDays * await _latePenaltyPerInstance();

    // Restored old rule (81ad48a): absence deducts a day wage —
    // base ÷ divisor (6 for weekly periods/staff, 30 otherwise) × the
    // absence multiplier setting — so absent days actually reduce the slip.
    // Daily staff already earn by present days only, so no extra deduction.
    double absenceMult = 1.0;
    try {
      final amRow = await (db.select(
        db.attendanceSettings,
      )..where((t) => t.settingKey.equals('absence_penalty_days_multiplier')))
          .getSingleOrNull();
      absenceMult = double.tryParse(amRow?.settingValue ?? '1') ?? 1.0;
    } catch (_) {}
    final divisor =
        (isWeeklyPeriod || staff.employmentType == 'weekly') ? 6.0 : 30.0;
    final absenceDeduction = staff.employmentType == 'daily'
        ? 0.0
        : attendanceSummary.absentDays * (staff.basicSalary / divisor) * absenceMult;

    final deductions =
        totalAdvances + penaltiesTotal + lateDeduction + absenceDeduction;

    final netSalary = basicSalary + overtimePay + allowancesTotal + rewardsTotal - deductions;

    await db.into(db.payrollTable).insert(
          PayrollTableCompanion.insert(
            staffId: staffId,
            payrollPeriod: payrollPeriod,
            periodStart: periodStart,
            periodEnd: periodEnd,
            basicSalary: basicSalary,
            overtimeHours: Value(attendanceSummary.totalOvertime),
            overtimeRate: Value(hourlyBase),
            overtimePay: Value(overtimePay),
            allowances: Value(allowancesTotal),
            deductions: Value(deductions),
            advances: Value(totalAdvances),
            netSalary: netSalary,
            workingDays: Value(attendanceSummary.totalDays),
            presentDays: Value(attendanceSummary.presentDays),
            absentDays: Value(attendanceSummary.absentDays),
            leaveDays: Value(attendanceSummary.leaveDays),
            rewardsTotal: Value(rewardsTotal),
            penaltiesTotal: Value(penaltiesTotal),
            lateDays: Value(attendanceSummary.lateDays),
            lateDeduction: Value(lateDeduction),
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

  /// Weekly bounds (restored locked rules from the old payroll): the week
  /// runs Saturday → Thursday (6 days), payday is Thursday. The week belongs
  /// to its Thursday's month, and Wn is that Thursday's order within its
  /// month (1..5). Example: Thu 2026-09-03 → W1 = Sat 2026-08-29 .. Thu 2026-09-03.
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
    final end = DateTime(thursday.year, thursday.month, thursday.day, 23, 59, 59);
    return (start, end);
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

  AttendanceSummary({
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.lateDays,
    required this.totalHours,
    required this.totalOvertime,
    this.totalLateMinutes = 0,
  });

  double get attendanceRate => totalDays > 0 ? presentDays / totalDays : 0.0;

  double get averageHoursPerDay =>
      presentDays > 0 ? totalHours / presentDays : 0.0;
}
