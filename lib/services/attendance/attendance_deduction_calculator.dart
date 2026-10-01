import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_shift_bounds.dart';

/// القاعدة الوحيدة لخصومات الحضور.
///
/// السبب في وجود الملف: كارت الحضور في `attendance_page.dart` وكشف المرتب
/// في `staff_management_service.dart` كان كل واحد فيهم بيتحسب بصيغة
/// مستقلة (سعر ساعة مختلف، نقطة بدء التأخير مختلفة، وخصم الإذن موجود في
/// واحد ومش موجود في التاني) — فبيطلع رقم مختلف لنفس الموظف ونفس الفترة.
/// أي تعديل هنا بيوصل للاثنين مع بعض، وفيه test واحد بقفل القواعد دي.
///
/// **[القواعد]**
/// * سعر الساعة: `hourlyRate` إن كان أكبر من صفر، وإلا الأساسي ÷ 8 لليومي،
///   ÷ 48 للأسبوعي، ÷ 160 الشهري (20 يوم × 8 ساعات). ساعة محفوظة بصفر
///   معناها "غير مضبوطة" مش "سعر صفر"، عشان ما تظلمش الموظف.
/// * التأخير: الدقائق **بعد نهاية فترة السماح فقط** — ما قبل السماح مش
///   بيتخصم (القاعدة دي مقفولة في `attendance_late_penalty_test.dart`).
/// * الإذن/الانصراف المبكر: الوقت اللي فات فعلياً (وقت الانصراف، وإلا نافذة
///   الإذن الساعية المحفوظة في الملاحظات). الإجازة والإذن اليومي المعفي
///   (من غير وقت) مش بيتخصموا.
/// * الغياب: `day_wage` → أجر اليوم (الأساسي ÷ 6 أسبوعي ÷ 30 شهري)، أو
///   `fixed` → مبلغ ثابت، مضروبين في `absence_penalty_days_multiplier`.
///   الموظف اليومي بيأخذ أجر أيام الحضور بس، فمفيش خصم غياب إضافي.
class AttendanceDeductionRules {
  /// نافذة الإذن الساعية المحفوظة في الملاحظات: 'من 09:00 إلى 12:00'.
  static final RegExp permissionWindow = RegExp(
    r'من\s*(\d{1,2}):(\d{2})\s*إلى\s*(\d{1,2}):(\d{2})',
  );

  /// إذن ساعي أو مخصص مسجل في الملاحظات مثل: '[إذن مخصص - مع الخصم - 2.5 ساعة]'
  static final RegExp customHoursPattern = RegExp(
    r'(?:إذن|مخصص).*?(\d+(?:\.\d+)?)\s*س(?:اعة)?',
  );

  static double customHoursFromNotes(String? notes) {
    if (notes == null) return 0.0;
    final m = customHoursPattern.firstMatch(notes);
    if (m == null) return 0.0;
    return double.tryParse(m.group(1)!) ?? 0.0;
  }

  /// -1 يعني "لا وقت مسجل".
  static int _minutesOf(DateTime? t) =>
      t == null ? -1 : (t.hour * 60 + t.minute);

  /// يوم عمل خارج الجدول انتهى بعد نهاية الدوام (وردية بتعدّي نص الليل).
  ///
  ///Such a day is neither a late day nor an early-leave day: the employee
  /// finished AFTER the scheduled end, so there is nothing left to dock and the
  /// hours past the end are overtime instead.
  ///
  /// The bounds live in [AttendanceShiftBounds] so the engine and this class
  /// cannot drift apart; see that file for why the 06:00 / 14h limits exist.
  static bool isOffScheduleMidnightCrossing(Attendance r) =>
      AttendanceShiftBounds.isOffScheduleMidnightCrossing(
        co: r.checkOutTime,
        ci: r.checkInTime,
      );

  /// معامل عدد الأيام في الشهر: 30 يوم عمل (الأساس المعتمد في baseline
  /// 5eb58db — `hourlyRate = basicSalary / dailyDivisor / standardHoursPerDay`).
  static const int monthlyDayDivisor = 30;
  static const int weeklyDayDivisor = 6;
  static const double defaultStandardHoursPerDay = 8.0;

  /// سعر ساعة الموظف — القاعدة الوحيدة، مستعملة في الحضور والمرتب مع بعض.
  ///
  /// APPROVED BUSINESS RULE (v72):
  ///   hourly = basicSalary / dailyDivisor / standardHoursPerDay
  ///
  /// monthly 6000 → 6000 / 30 / 8 = 25
  /// weekly  1200 → 1200 /  6 / 8 = 25
  ///
  /// This divisor MUST travel together with the overtime multiplier. The old
  /// /160 divisor was self-cancelling with a *missing* multiplier
  /// (160 = 240/1.5); applying the multiplier on top of /160 would overpay
  /// overtime by 50%.
  static double hourlyOf(
    Staff staff, {
    required bool weeklyPeriod,
    double standardHoursPerDay = defaultStandardHoursPerDay,
  }) {
    if (staff.hourlyRate != null && staff.hourlyRate! > 0) {
      return staff.hourlyRate!;
    }
    if (standardHoursPerDay <= 0) standardHoursPerDay = defaultStandardHoursPerDay;
    if (staff.employmentType == 'daily') return staff.basicSalary / 8.0;
    final divisor = (weeklyPeriod || staff.employmentType == 'weekly')
        ? weeklyDayDivisor
        : monthlyDayDivisor;
    return staff.basicSalary / divisor / standardHoursPerDay;
  }

  /// معامل مضاعف خصم التأخير.
  ///
  /// APPROVED BUSINESS RULE (v72) — a single resolved value shared by payroll
  /// and the Employee Details display so they cannot diverge:
  ///
  ///   lateMultiplier =
  ///       configuredLatePenaltyPerHour > 0
  ///           ? configuredLatePenaltyPerHour
  ///           : 1.5;
  ///
  /// The setting key is `late_penalty_per_hour`. Its baseline default of 0 meant
  /// "not configured", so 0 falls back to 1.5 rather than silently zeroing the
  /// deduction.
  static const double defaultLateMultiplier = 1.5;

  static double resolveLateMultiplier(double? configuredLatePenaltyPerHour) {
    if (configuredLatePenaltyPerHour == null) return defaultLateMultiplier;
    if (!(configuredLatePenaltyPerHour > 0)) return defaultLateMultiplier;
    return configuredLatePenaltyPerHour;
  }

  /// أجر اليوم — أساس خصم الغياب في نمط day_wage.
  static double dayWageOf(Staff staff, {required bool weeklyPeriod}) {
    final divisor = (weeklyPeriod || staff.employmentType == 'weekly')
        ? weeklyDayDivisor.toDouble()
        : monthlyDayDivisor.toDouble();
    return staff.basicSalary / divisor;
  }

  /// هل السجل ده إذن / انصراف مبكر قابل للخصم؟
  ///
  /// Single source of truth for BOTH the summary card and its detail dialog —
  /// the card and the dialog must never disagree about what counts as a
  /// permission.
  static bool isPermissionRecord(Attendance r, {required int workEndMinutes}) {
    // v72 restored column: authoritative marker written by the current build.
    if (r.excused) return true;
    if (r.status == 'excused' || r.status == 'excused_late') return true;
    if (r.status == 'leave' &&
        r.leaveType != null &&
        r.leaveType!.trim().isNotEmpty) {
      return true;
    }
    // v72 restored column: admin-entered partial permission hours.
    if (r.permissionHours > 0 || r.excusedHours > 0) return true;
    if (customHoursFromNotes(r.notes) > 0) return true;
    // An off-schedule day that ran through the night is NOT an early leave. She
    // finished after the scheduled end, so `workEnd - checkOut` below would
    // charge her for the hours she ADDED.
    //
    // Placement is load-bearing: this sits AFTER every admin-asserted marker
    // above (excused flag, excused status, leave+leaveType, permissionHours /
    // excusedHours, notes window). A supervisor's explicit permission must win
    // over a timestamp heuristic.
    if (isOffScheduleMidnightCrossing(r)) return false;
    final co = _minutesOf(r.checkOutTime);
    if (co < 0) return false;
    return co < workEndMinutes &&
        (r.status == 'present' || r.status == 'late');
  }

  /// الدقائق المخصومة من سجل واحد (انصراف مبكر / إذن ساعي).
  static int permissionMinutesOf(Attendance r, {required int workEndMinutes}) {
    if (!isPermissionRecord(r, workEndMinutes: workEndMinutes)) return 0;
    if (r.status == 'leave' && r.excusedHours <= 0 && r.permissionHours <= 0) {
      return 0; // إجازة معتمدة = ليست خصماً
    }
    // A fully exempt day (excused with no hours) deducts nothing.
    if (r.excused && r.excusedHours <= 0) return 0;
    // Explicit partial permission recorded on the row wins.
    final explicitHours = r.excusedHours > 0
        ? r.excusedHours
        : (!r.excused && r.permissionHours > 0 ? r.permissionHours : 0.0);
    if (explicitHours > 0) return (explicitHours * 60).round();
    final co = _minutesOf(r.checkOutTime);
    // Same guard as isPermissionRecord, needed independently: that method can
    // return true via the notes-window marker above while `explicitHours` is
    // still 0, in which case the early return above does not fire and control
    // reaches this clock maths - which would otherwise dock the phantom
    // `workEnd - midnight` span.
    if (co >= 0) {
      if (isOffScheduleMidnightCrossing(r)) return 0;
      return co < workEndMinutes ? workEndMinutes - co : 0;
    }
    final m = permissionWindow.firstMatch(r.notes ?? '');
    if (m != null) {
      final from = (int.tryParse(m.group(1)!) ?? 0) * 60 +
          (int.tryParse(m.group(2)!) ?? 0);
      final to = (int.tryParse(m.group(3)!) ?? 0) * 60 +
          (int.tryParse(m.group(4)!) ?? 0);
      return to > from ? to - from : 0;
    }
    final noteHours = customHoursFromNotes(r.notes);
    if (noteHours > 0) {
      if (r.excused || (r.notes != null && r.notes!.contains('بدون خصم'))) return 0;
      return (noteHours * 60).round();
    }
    return 0; // إذن يوم كامل معفي
  }

  /// دقائق التأخير الفعلية — من بداية الدوام، وصفر للمعفي.
  ///
  /// APPROVED BUSINESS RULE (v72), baseline 5eb58db:871/900:
  ///   lateMinutes = checkIn - workStart
  ///
  /// Grace decides only WHETHER the row counts as late at all: arriving inside
  /// the grace window is not late and deducts nothing. Once the row IS late,
  /// the minutes deducted are measured from the shift start, so 09:20 with a
  /// 15-minute grace is 20 late minutes, not 5.
  /// v73: a check-in at or after the scheduled END is an alternative start, not
  /// lateness - the shift she was "late" to had already closed. That exemption
  /// additionally requires the day to have actually run past the scheduled end
  /// (see [isOffScheduleMidnightCrossing]); without that second condition a
  /// genuinely 9h-late employee who leaves at 18:00 would be wrongly excused.
  static int lateMinutesOf(
    Attendance r, {
    required int workStartMinutes,
    required int workEndMinutes,
    required int graceMinutes,
  }) {
    // The v72 `excused` flag is the authoritative permission marker, so an
    // excused row deducts nothing for lateness no matter which `status`
    // string an older build happened to write.
    if (r.excused) return 0;
    if (r.status == 'excused' || r.status == 'excused_late') return 0;
    final ci = _minutesOf(r.checkInTime);
    if (ci < 0) return 0;
    // Grace only decides WHETHER the row is late...
    final graceEnd = workStartMinutes + graceMinutes;
    if (ci <= graceEnd) return 0;
    // ...but the deducted minutes are measured from the shift start.
    // v73 exemption for an off-schedule start: checked in at/after the scheduled
    // end AND the day ran past that end. The conjunction matters - see the note
    // on this method.
    if (ci >= workEndMinutes && isOffScheduleMidnightCrossing(r)) return 0;
    return ci - workStartMinutes;
  }
}

/// نتيجة الحساب — نفس الأرقام اللي بتظهر في كارت الحضور وفي تفصيل كشف
/// المرتب، عشان ما يحصلش اختلاف بين الشاشتين.
class AttendanceDeductionResult {
  final int lateDays;
  final int totalLateMinutes;
  final int permissionDays;
  final int totalPermissionMinutes;
  final int permissionRecords;
  final int absentDays;

  final double hourly;
  final double dayWage;
  final double lateMultiplier;
  final double absenceMultiplier;
  final String absenceMode;
  final double fixedAbsenceAmount;

  final double lateDeduction;
  final double permissionDeduction;
  final double absenceDeduction;

  const AttendanceDeductionResult({
    required this.lateDays,
    required this.totalLateMinutes,
    required this.permissionDays,
    required this.totalPermissionMinutes,
    required this.permissionRecords,
    required this.absentDays,
    required this.hourly,
    required this.dayWage,
    required this.lateMultiplier,
    required this.absenceMultiplier,
    required this.absenceMode,
    required this.fixedAbsenceAmount,
    required this.lateDeduction,
    required this.permissionDeduction,
    required this.absenceDeduction,
  });

  /// إجمالي خصومات الحضور (من غير السلف والجزاءات — دي بتتجمع في المرتب).
  double get total => lateDeduction + permissionDeduction + absenceDeduction;
}

/// يحسب خصومات الحضور من سجلات فترة معيّنة. دالة نقية (مش بتلمس الـDB)
/// عشان تستخدمها شاشة الحضور وكشف المرتب بنفس القيم بالظبط.
AttendanceDeductionResult computeAttendanceDeductions({
  required List<Attendance> records,
  required Staff staff,
  required bool weeklyPeriod,
  required int workStartMinutes,
  required int workEndMinutes,
  required int graceMinutes,
  double lateMultiplier = 1.5,
  double absenceMultiplier = 1.0,
  String absenceMode = 'day_wage',
  double fixedAbsenceAmount = 0.0,
  double standardHoursPerDay = AttendanceDeductionRules
      .defaultStandardHoursPerDay,
}) {
  final hourly = AttendanceDeductionRules.hourlyOf(
    staff,
    weeklyPeriod: weeklyPeriod,
    standardHoursPerDay: standardHoursPerDay,
  );
  final dayWage = AttendanceDeductionRules.dayWageOf(
    staff,
    weeklyPeriod: weeklyPeriod,
  );

  var lateDays = 0;
  var totalLateMinutes = 0;
  var permissionDays = 0;
  var totalPermissionMinutes = 0;
  var permissionRecords = 0;
  var absentDays = 0;

  for (final r in records) {
    if (r.status == 'absent') absentDays++;

    final lm = AttendanceDeductionRules.lateMinutesOf(
      r,
      workStartMinutes: workStartMinutes,
      workEndMinutes: workEndMinutes,
      graceMinutes: graceMinutes,
    );
    if (lm > 0) {
      lateDays++;
      totalLateMinutes += lm;
    }

    if (AttendanceDeductionRules.isPermissionRecord(
      r,
      workEndMinutes: workEndMinutes,
    )) {
      permissionRecords++;
      final pm = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEndMinutes,
      );
      if (pm > 0) {
        permissionDays++;
        totalPermissionMinutes += pm;
      }
    }
  }

  final absenceBase = absenceMode == 'fixed' ? fixedAbsenceAmount : dayWage;
  final absenceDeduction = staff.employmentType == 'daily'
      ? 0.0
      : absentDays * absenceBase * absenceMultiplier;

  return AttendanceDeductionResult(
    lateDays: lateDays,
    totalLateMinutes: totalLateMinutes,
    permissionDays: permissionDays,
    totalPermissionMinutes: totalPermissionMinutes,
    permissionRecords: permissionRecords,
    absentDays: absentDays,
    hourly: hourly,
    dayWage: dayWage,
    lateMultiplier: lateMultiplier,
    absenceMultiplier: absenceMultiplier,
    absenceMode: absenceMode,
    fixedAbsenceAmount: fixedAbsenceAmount,
    lateDeduction: (totalLateMinutes / 60.0) * hourly * lateMultiplier,
    permissionDeduction: (totalPermissionMinutes / 60.0) * hourly,
    absenceDeduction: absenceDeduction,
  );
}
