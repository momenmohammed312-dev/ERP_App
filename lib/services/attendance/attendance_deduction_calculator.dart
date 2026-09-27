import 'package:pos_offline_desktop/core/database/app_database.dart';

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

  /// -1 يعني "لا وقت مسجل".
  static int _minutesOf(DateTime? t) =>
      t == null ? -1 : (t.hour * 60 + t.minute);

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
  static bool isPermissionRecord(Attendance r, {required int workEndMinutes}) {
    if (r.status == 'excused' || r.status == 'excused_late') return true;
    if (r.status == 'leave' &&
        r.leaveType != null &&
        r.leaveType!.trim().isNotEmpty) {
      return true;
    }
    final co = _minutesOf(r.checkOutTime);
    if (co < 0) return false;
    return co < workEndMinutes &&
        (r.status == 'present' || r.status == 'late');
  }

  /// الدقائق المخصومة من سجل واحد (انصراف مبكر / إذن ساعي).
  static int permissionMinutesOf(Attendance r, {required int workEndMinutes}) {
    if (!isPermissionRecord(r, workEndMinutes: workEndMinutes)) return 0;
    if (r.status == 'leave') return 0; // إجازة معتمدة = ليست خصماً
    final co = _minutesOf(r.checkOutTime);
    if (co >= 0) return co < workEndMinutes ? workEndMinutes - co : 0;
    final m = permissionWindow.firstMatch(r.notes ?? '');
    if (m == null) return 0; // إذن يوم كامل معفي
    final from = (int.tryParse(m.group(1)!) ?? 0) * 60 +
        (int.tryParse(m.group(2)!) ?? 0);
    final to = (int.tryParse(m.group(3)!) ?? 0) * 60 +
        (int.tryParse(m.group(4)!) ?? 0);
    return to > from ? to - from : 0;
  }

  /// دقائق التأخير الفعلية — بعد نهاية السماح فقط، وصفر للمعفي.
  static int lateMinutesOf(
    Attendance r, {
    required int workStartMinutes,
    required int graceMinutes,
  }) {
    if (r.status == 'excused' || r.status == 'excused_late') return 0;
    final ci = _minutesOf(r.checkInTime);
    if (ci < 0) return 0;
    final graceEnd = workStartMinutes + graceMinutes;
    if (ci <= graceEnd) return 0;
    return ci - graceEnd;
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
