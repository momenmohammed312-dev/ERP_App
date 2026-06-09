// ignore_for_file: argument_type_not_assignable
import 'dart:math';
import 'package:drift/drift.dart';
import '../core/database/app_database.dart';
import '../core/database/dao/staff_management_dao.dart';
import '../core/models/user_model.dart';
import '../core/services/validation/permission_validator.dart';

class StaffManagementService {
  final StaffManagementDao _dao;

  StaffManagementService(this._dao);

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
  }) async {
    PermissionValidator.requirePermission(user, Permission.editSettings, 'إضافة موظف');
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
  }) async {
    PermissionValidator.requirePermission(user, Permission.editSettings, 'تعديل موظف');
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
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> terminateStaff(User? user, String staffId) async {
    PermissionValidator.requirePermission(user, Permission.editSettings, 'إنهاء خدمة موظف');
    await updateStaffInfo(user, staffId: staffId, status: 'terminated');
  }

  // ATTENDANCE MANAGEMENT

  Future<void> recordCheckIn(String staffId, {String? location}) async {
    await _dao.checkIn(staffId, location: location);
  }

  Future<void> recordCheckOut(String staffId, {String? location}) async {
    await _dao.checkOut(staffId, location: location);
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

    for (final record in attendanceRecords) {
      switch (record.status) {
        case 'present':
          presentDays++;
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
    PermissionValidator.requirePermission(user, Permission.editSettings, 'طلب سلفة');
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

  Future<void> calculatePayroll(User? user, String staffId, String payrollPeriod) async {
    PermissionValidator.requirePermission(user, Permission.editSettings, 'حساب الرواتب');
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

    // Get advances to deduct
    final advances = await _dao.getAdvancesByStaff(staffId);
    final approvedAdvances = advances.where(
      (a) => a.status == 'approved' && a.paymentDate == null,
    );
    final totalAdvances = approvedAdvances.fold<double>(
      0,
      (sum, a) => sum + a.amount,
    );

    // Get rewards and penalties for the period
    final db = _dao.attachedDatabase;
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

    // Calculate payroll
    final basicSalary = staff.basicSalary;
    final overtimePay =
        attendanceSummary.totalOvertime *
        (staff.hourlyRate ?? basicSalary / 160);

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
            overtimeRate: Value(staff.hourlyRate ?? basicSalary / 160),
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
            status: 'calculated',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> payAdvance(User? user, int advanceId, String paymentMethod) async {
    PermissionValidator.requirePermission(user, Permission.editSettings, 'صرف سلفة');
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
    PermissionValidator.requirePermission(user, Permission.editSettings, 'صرف رواتب');
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
    PermissionValidator.requirePermission(user, Permission.editSettings, 'تقييم أداء');
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

  AttendanceSummary({
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.lateDays,
    required this.totalHours,
    required this.totalOvertime,
  });

  double get attendanceRate => totalDays > 0 ? presentDays / totalDays : 0.0;

  double get averageHoursPerDay =>
      presentDays > 0 ? totalHours / presentDays : 0.0;
}
